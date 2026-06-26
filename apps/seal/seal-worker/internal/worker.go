package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

const (
	pendingQueue    = "seal:jobs"
	processingQueue = "seal:processing"
	resultsQueue    = "seal:results"
	dlqQueue        = "seal:dlq"
	maxJobRetries   = 3
)

type JobMessage struct {
	DocumentID  string `json:"document_id"`
	InputText   string `json:"input_text"`
	TraceParent string `json:"traceparent,omitempty"`
}

type ResultMessage struct {
	DocumentID  string `json:"document_id"`
	Status      string `json:"status"`
	S3Path      string `json:"s3_path"`
	Error       string `json:"error"`
	TraceParent string `json:"traceparent,omitempty"`
}

type Worker struct {
	redis       *redis.Client
	storage     *Storage
	signer      *Signer
	pollTimeout time.Duration
	tracer      trace.Tracer
}

func NewWorker(redisClient *redis.Client, storage *Storage, signer *Signer, pollTimeout time.Duration) *Worker {
	return &Worker{
		redis:       redisClient,
		storage:     storage,
		signer:      signer,
		pollTimeout: pollTimeout,
		tracer:      otel.Tracer("seal-worker"),
	}
}

func (w *Worker) Run(ctx context.Context) error {
	slog.Info("worker started", "poll_timeout", w.pollTimeout)

	for {
		select {
		case <-ctx.Done():
			slog.Info("worker shutting down, finishing in-flight job")
			return nil
		default:
		}

		jobStr, err := w.redis.BLMove(ctx, pendingQueue, processingQueue, "LEFT", "RIGHT", w.pollTimeout).Result()
		if err != nil {
			if errors.Is(err, redis.Nil) {
				continue
			}
			return fmt.Errorf("blmove: %w", err)
		}

		w.process(ctx, jobStr)
	}
}

func (w *Worker) process(ctx context.Context, jobStr string) {
	start := time.Now()

	var msg JobMessage
	if err := json.Unmarshal([]byte(jobStr), &msg); err != nil {
		slog.Error("invalid job message JSON", "job", jobStr, "error", err)
		w.removeFromProcessing(ctx, jobStr)
		return
	}

	jobCtx := ctx
	if msg.TraceParent != "" {
		propagator := otel.GetTextMapPropagator()
		carrier := propagation.MapCarrier{"traceparent": msg.TraceParent}
		jobCtx = propagator.Extract(ctx, carrier)
	}

	jobCtx, span := w.tracer.Start(jobCtx, "ProcessJob",
		trace.WithAttributes(
			attribute.String("document.id", msg.DocumentID),
		),
	)
	defer span.End()

	id, err := uuid.Parse(msg.DocumentID)
	if err != nil {
		slog.Error("invalid document ID in job", "document_id", msg.DocumentID, "error", err)
		w.removeFromProcessing(jobCtx, jobStr)
		return
	}

	if msg.InputText == "" {
		slog.Error("empty input text in job", "document_id", id)
		_ = w.pushResult(jobCtx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      "empty input text",
		})
		w.retryOrDLQ(jobCtx, jobStr)
		return
	}

	slog.Info("processing job", "document_id", id)

	data, err := GeneratePDF(msg.InputText)
	if err != nil {
		slog.Error("generate pdf", "document_id", id, "error", err)
		span.RecordError(err)
		_ = w.pushResult(jobCtx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      fmt.Sprintf("pdf generation: %v", err),
		})
		w.retryOrDLQ(jobCtx, jobStr)
		return
	}
	slog.Info("pdf generated",
		"document_id", id,
		"size_bytes", len(data),
		"text_length", len(msg.InputText),
	)

	if w.signer != nil {
		signStart := time.Now()

		_, signSpan := w.tracer.Start(jobCtx, "Sign",
			trace.WithAttributes(attribute.String("document.id", id.String())),
		)
		signed, err := w.signer.Sign(jobCtx, data)
		if err != nil {
			slog.Error("sign pdf", "document_id", id, "error", err)
			signSpan.RecordError(err)
			signSpan.End()
			span.RecordError(err)
			_ = w.pushResult(jobCtx, ResultMessage{
				DocumentID: id.String(),
				Status:     "failed",
				Error:      fmt.Sprintf("pdf sign: %v", err),
			})
			w.retryOrDLQ(jobCtx, jobStr)
			return
		}
		signSpan.SetAttributes(attribute.Int("size_bytes", len(signed)))
		signSpan.End()
		slog.Info("pdf signed",
			"document_id", id,
			"duration", time.Since(signStart),
			"size_bytes", len(signed),
		)
		data = signed
	} else {
		slog.Warn("pdf not signed", "document_id", id, "reason", "no signer configured")
	}

	objectKey := id.String() + ".pdf"
	uploadStart := time.Now()

	_, uploadSpan := w.tracer.Start(jobCtx, "Upload",
		trace.WithAttributes(
			attribute.String("document.id", id.String()),
			attribute.String("object_key", objectKey),
		),
	)
	if err := w.storage.Upload(jobCtx, objectKey, data); err != nil {
		slog.Error("upload pdf", "document_id", id, "error", err)
		uploadSpan.RecordError(err)
		uploadSpan.End()
		span.RecordError(err)
		_ = w.pushResult(jobCtx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      fmt.Sprintf("upload: %v", err),
		})
		w.retryOrDLQ(jobCtx, jobStr)
		return
	}
	uploadSpan.End()
	slog.Info("pdf uploaded",
		"document_id", id,
		"object_key", objectKey,
		"size_bytes", len(data),
		"duration", time.Since(uploadStart),
	)

	if err := w.pushResult(jobCtx, ResultMessage{
		DocumentID: id.String(),
		Status:     "completed",
		S3Path:     objectKey,
	}); err != nil {
		slog.Error("push result", "document_id", id, "error", err)
	} else {
		slog.Info("result pushed", "document_id", id, "status", "completed", "s3_path", objectKey)
	}

	w.removeFromProcessing(jobCtx, jobStr)
	jobsProcessedTotal.WithLabelValues("ok").Inc()
	jobDurationSeconds.Observe(time.Since(start).Seconds())
	slog.Info("job completed",
		"document_id", id,
		"duration", time.Since(start),
		"total_bytes", len(data),
	)
}

func (w *Worker) pushResult(ctx context.Context, result ResultMessage) error {
	propagator := otel.GetTextMapPropagator()
	carrier := propagation.MapCarrier{}
	propagator.Inject(ctx, carrier)
	if tp, ok := carrier["traceparent"]; ok {
		result.TraceParent = tp
	}

	data, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("marshal result: %w", err)
	}
	return w.redis.RPush(ctx, resultsQueue, string(data)).Err()
}

func (w *Worker) retryOrDLQ(ctx context.Context, jobStr string) {
	count, err := w.redis.LLen(ctx, processingQueue).Result()
	if err != nil {
		slog.Error("check retry count", "error", err)
		w.pushToDLQ(ctx, jobStr)
		return
	}

	if count >= maxJobRetries {
		w.pushToDLQ(ctx, jobStr)
		return
	}

	if err := w.redis.LPush(ctx, pendingQueue, jobStr).Err(); err != nil {
		slog.Error("re-queue job", "job_str", jobStr, "error", err)
		w.pushToDLQ(ctx, jobStr)
	}
}

func (w *Worker) pushToDLQ(ctx context.Context, jobStr string) {
	if err := w.redis.LPush(ctx, dlqQueue, jobStr).Err(); err != nil {
		slog.Error("push to dlq", "job_str", jobStr, "error", err)
	}
	w.removeFromProcessing(ctx, jobStr)
}

func (w *Worker) removeFromProcessing(ctx context.Context, jobStr string) {
	if err := w.redis.LRem(ctx, processingQueue, 0, jobStr).Err(); err != nil {
		slog.Error("remove from processing", "job_str", jobStr, "error", err)
	}
}

var (
	jobsProcessedTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "jobs_processed_total",
		Help: "Total number of jobs processed",
	}, []string{"status"})

	jobDurationSeconds = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "job_duration_seconds",
		Help:    "Job processing duration in seconds",
		Buckets: prometheus.DefBuckets,
	})
)
