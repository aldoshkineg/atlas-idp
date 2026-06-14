package internal

import (
	"context"
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
	dlqQueue        = "text2pdf:dlq"
	maxJobRetries   = 3
)

type Worker struct {
	redis       *redis.Client
	repo        *Repository
	storage     *Storage
	pollTimeout time.Duration
}

func NewWorker(redisClient *redis.Client, repo *Repository, storage *Storage, pollTimeout time.Duration) *Worker {
	return &Worker{
		redis:       redisClient,
		repo:        repo,
		storage:     storage,
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

		jobID, err := w.redis.BLMove(ctx, pendingQueue, processingQueue, "LEFT", "RIGHT", w.pollTimeout).Result()
		if err != nil {
			if errors.Is(err, redis.Nil) {
				continue
			}
			return fmt.Errorf("blmove: %w", err)
		}

		w.process(ctx, jobID)
	}
}

func (w *Worker) process(ctx context.Context, jobID string) {
	start := time.Now()
	id, err := uuid.Parse(jobID)
	if err != nil {
		slog.Error("invalid job ID", "job_id", jobID, "error", err)
		w.removeFromProcessing(ctx, jobID)
		return
	}

	slog.Info("processing job", "document_id", id)

	doc, err := w.repo.GetDocument(ctx, id)
	if err != nil {
		slog.Error("get document", "document_id", id, "error", err)
		w.retryOrDLQ(ctx, jobID)
		return
	}
	if doc == nil {
		slog.Warn("document not found", "document_id", id)
		w.removeFromProcessing(ctx, jobID)
		return
	}

	if err := w.repo.UpdateStatus(ctx, id, "processing", "", ""); err != nil {
		slog.Error("update status to processing", "document_id", id, "error", err)
	}

	data, err := GeneratePDF(doc.InputText)
	if err != nil {
		slog.Error("generate pdf", "document_id", id, "error", err)
		w.handleFailure(ctx, id, jobID, fmt.Errorf("pdf generation: %w", err))
		return
	}

	objectKey := id.String() + ".pdf"
	if err := w.storage.Upload(ctx, objectKey, data); err != nil {
		slog.Error("upload pdf", "document_id", id, "error", err)
		w.handleFailure(ctx, id, jobID, fmt.Errorf("upload: %w", err))
		return
	}

	if err := w.repo.UpdateStatus(ctx, id, "completed", objectKey, ""); err != nil {
		slog.Error("update status to completed", "document_id", id, "error", err)
	}

	w.removeFromProcessing(ctx, jobID)
	jobsProcessedTotal.WithLabelValues("ok").Inc()
	jobDurationSeconds.Observe(time.Since(start).Seconds())
	slog.Info("job completed", "document_id", id, "duration", time.Since(start))
}

func (w *Worker) handleFailure(ctx context.Context, id uuid.UUID, jobID string, err error) {
	w.repo.UpdateStatus(ctx, id, "failed", "", err.Error())
	w.retryOrDLQ(ctx, jobID)
	jobsProcessedTotal.WithLabelValues("fail").Inc()
}

func (w *Worker) retryOrDLQ(ctx context.Context, jobID string) {
	count, err := w.redis.LLen(ctx, processingQueue).Result()
	if err != nil {
		slog.Error("check retry count", "error", err)
		w.pushToDLQ(ctx, jobID)
		return
	}

	if count >= maxJobRetries {
		w.pushToDLQ(ctx, jobID)
		return
	}

	if err := w.redis.LPush(ctx, pendingQueue, jobID).Err(); err != nil {
		slog.Error("re-queue job", "job_id", jobID, "error", err)
		w.pushToDLQ(ctx, jobID)
	}
}

func (w *Worker) pushToDLQ(ctx context.Context, jobID string) {
	if err := w.redis.LPush(ctx, dlqQueue, jobID).Err(); err != nil {
		slog.Error("push to dlq", "job_id", jobID, "error", err)
	}
	w.removeFromProcessing(ctx, jobID)
}

func (w *Worker) removeFromProcessing(ctx context.Context, jobID string) {
	if err := w.redis.LRem(ctx, processingQueue, 0, jobID).Err(); err != nil {
		slog.Error("remove from processing", "job_id", jobID, "error", err)
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
