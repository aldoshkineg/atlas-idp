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
)

const (
	pendingQueue    = "text2pdf:jobs"
	processingQueue = "text2pdf:processing"
	resultsQueue    = "text2pdf:results"
	dlqQueue        = "text2pdf:dlq"
	maxJobRetries   = 3
)

type JobMessage struct {
	DocumentID string `json:"document_id"`
	InputText  string `json:"input_text"`
}

type ResultMessage struct {
	DocumentID string `json:"document_id"`
	Status     string `json:"status"`
	S3Path     string `json:"s3_path"`
	Error      string `json:"error"`
}

type Worker struct {
	redis       *redis.Client
	storage     *Storage
	signer      *Signer
	pollTimeout time.Duration
}

func NewWorker(redisClient *redis.Client, storage *Storage, signer *Signer, pollTimeout time.Duration) *Worker {
	return &Worker{
		redis:       redisClient,
		storage:     storage,
		signer:      signer,
		pollTimeout: pollTimeout,
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

	id, err := uuid.Parse(msg.DocumentID)
	if err != nil {
		slog.Error("invalid document ID in job", "document_id", msg.DocumentID, "error", err)
		w.removeFromProcessing(ctx, jobStr)
		return
	}

	if msg.InputText == "" {
		slog.Error("empty input text in job", "document_id", id)
		w.pushResult(ctx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      "empty input text",
		})
		w.retryOrDLQ(ctx, jobStr)
		return
	}

	slog.Info("processing job", "document_id", id)

	data, err := GeneratePDF(msg.InputText)
	if err != nil {
		slog.Error("generate pdf", "document_id", id, "error", err)
		w.pushResult(ctx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      fmt.Sprintf("pdf generation: %v", err),
		})
		w.retryOrDLQ(ctx, jobStr)
		return
	}
	slog.Info("pdf generated",
		"document_id", id,
		"size_bytes", len(data),
		"text_length", len(msg.InputText),
	)

	if w.signer != nil {
		signStart := time.Now()
		signed, err := w.signer.Sign(ctx, data)
		if err != nil {
			slog.Error("sign pdf", "document_id", id, "error", err)
			w.pushResult(ctx, ResultMessage{
				DocumentID: id.String(),
				Status:     "failed",
				Error:      fmt.Sprintf("pdf sign: %v", err),
			})
			w.retryOrDLQ(ctx, jobStr)
			return
		}
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
	if err := w.storage.Upload(ctx, objectKey, data); err != nil {
		slog.Error("upload pdf", "document_id", id, "error", err)
		w.pushResult(ctx, ResultMessage{
			DocumentID: id.String(),
			Status:     "failed",
			Error:      fmt.Sprintf("upload: %v", err),
		})
		w.retryOrDLQ(ctx, jobStr)
		return
	}
	slog.Info("pdf uploaded",
		"document_id", id,
		"object_key", objectKey,
		"size_bytes", len(data),
		"duration", time.Since(uploadStart),
	)

	if err := w.pushResult(ctx, ResultMessage{
		DocumentID: id.String(),
		Status:     "completed",
		S3Path:     objectKey,
	}); err != nil {
		slog.Error("push result", "document_id", id, "error", err)
	} else {
		slog.Info("result pushed", "document_id", id, "status", "completed", "s3_path", objectKey)
	}

	w.removeFromProcessing(ctx, jobStr)
	jobsProcessedTotal.WithLabelValues("ok").Inc()
	jobDurationSeconds.Observe(time.Since(start).Seconds())
	slog.Info("job completed",
		"document_id", id,
		"duration", time.Since(start),
		"total_bytes", len(data),
	)
}

func (w *Worker) pushResult(ctx context.Context, result ResultMessage) error {
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
