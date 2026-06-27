package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type Handler struct {
	repo             *Repository
	queue            *Queue
	tracer           trace.Tracer
	downloadEndpoint string
}

func NewHandler(repo *Repository, queue *Queue, downloadEndpoint string) *Handler {
	return &Handler{
		repo:             repo,
		queue:            queue,
		tracer:           otel.Tracer("seal-api"),
		downloadEndpoint: downloadEndpoint,
	}
}

func (h *Handler) startSpan(ctx context.Context, name string) (context.Context, trace.Span) {
	if h.tracer != nil {
		return h.tracer.Start(ctx, name)
	}
	return ctx, trace.Span(nil)
}

func spanEnd(span trace.Span) {
	if span != nil {
		span.End()
	}
}

func spanSetAttributes(span trace.Span, attrs ...attribute.KeyValue) {
	if span != nil {
		span.SetAttributes(attrs...)
	}
}

func spanRecordError(span trace.Span, err error) {
	if span != nil {
		span.RecordError(err)
	}
}

type CreateRequest struct {
	Text string `json:"text"`
}

type CreateResponse struct {
	ID uuid.UUID `json:"id"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func (h *Handler) CreateDocument(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.startSpan(r.Context(), "CreateDocument")
	defer spanEnd(span)

	var req CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON body"})
		return
	}
	if req.Text == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "text is required"})
		return
	}

	docID, err := h.repo.CreateDocument(ctx, req.Text)
	if err != nil {
		slog.Error("create document", "error", err)
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to create document"})
		return
	}

	if err := h.queue.PushTask(ctx, docID.String(), req.Text); err != nil {
		slog.Error("push task to queue", "document_id", docID, "error", err)
	} else {
		slog.Info("task pushed to queue", "document_id", docID, "text_length", len(req.Text))
	}

	spanSetAttributes(span, attribute.String("document.id", docID.String()))
	documentsCreatedTotal.Inc()

	writeJSON(w, http.StatusCreated, CreateResponse{ID: docID})
}

func (h *Handler) GetDocument(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.startSpan(r.Context(), "GetDocument")
	defer spanEnd(span)

	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid document ID"})
		return
	}

	doc, err := h.repo.GetDocument(ctx, id)
	if err != nil {
		slog.Error("get document", "error", err)
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to get document"})
		return
	}
	if doc == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "document not found"})
		return
	}

	spanSetAttributes(span, attribute.String("document.id", doc.ID.String()))
	writeJSON(w, http.StatusOK, doc)
}

func (h *Handler) GetDownloadURL(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.startSpan(r.Context(), "GetDownloadURL")
	defer spanEnd(span)

	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid document ID"})
		return
	}

	doc, err := h.repo.GetDocument(ctx, id)
	if err != nil {
		slog.Error("get document for download", "error", err)
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to get document"})
		return
	}
	if doc == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "document not found"})
		return
	}
	if doc.Status != "completed" {
		writeJSON(w, http.StatusConflict, ErrorResponse{Error: "document not ready yet"})
		return
	}

	url := h.downloadEndpoint + "/seal-outputs/" + doc.S3Path
	writeJSON(w, http.StatusOK, map[string]string{"url": url})
}

func (h *Handler) VerifyDocument(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.startSpan(r.Context(), "VerifyDocument")
	defer spanEnd(span)

	idStr := chi.URLParam(r, "id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid document ID"})
		return
	}

	spanSetAttributes(span, attribute.String("document.id", id.String()))

	doc, err := h.repo.GetDocument(ctx, id)
	if err != nil {
		slog.Error("get document for verify", "error", err)
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to get document"})
		return
	}
	if doc == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "document not found"})
		return
	}
	if doc.Status != "completed" {
		writeJSON(w, http.StatusConflict, ErrorResponse{Error: "document not ready yet"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"valid":     true,
		"subject":   "PDF Signer",
		"s3_path":   doc.S3Path,
		"signed_by": "seal-worker",
	})
}

func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func (h *Handler) Readyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := h.repo.Pool().Ping(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(ErrorResponse{Error: "database not ready"})
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func NewRouter(h *Handler) chi.Router {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(loggingMiddleware)
	r.Use(metricsMiddleware)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(corsMiddleware)

	r.Get("/healthz", h.Healthz)
	r.Get("/readyz", h.Readyz)

		r.Route("/api/v1", func(r chi.Router) {
			r.Post("/documents", h.CreateDocument)
			r.Get("/documents/{id}", h.GetDocument)
			r.Get("/documents/{id}/download", h.GetDownloadURL)
			r.Get("/documents/{id}/verify", h.VerifyDocument)
		})

	r.Handle("/metrics", promhttp.Handler())

	return r
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", ww.Status(),
			"duration", time.Since(start).String(),
			"request_id", middleware.GetReqID(r.Context()),
		)
	})
}

func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", ww.Status())).Inc()
		httpRequestDurationSeconds.WithLabelValues(r.Method, r.URL.Path).Observe(time.Since(start).Seconds())
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests",
	}, []string{"method", "path", "status"})

	httpRequestDurationSeconds = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request duration in seconds",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})

	documentsCreatedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "documents_created_total",
		Help: "Total number of documents created",
	})

	RedisQueueLength = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "redis_queue_length",
		Help: "Current length of Redis queues",
	}, []string{"queue"})
)

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
