package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aldoshkineg/atlas-idp/apps/seal-api/internal"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	cfg, err := internal.LoadConfig(ctx)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	setLogLevel(cfg.HTTP.LogLevel)

	if cfg.Telemetry.OTLPEndpoint != "" {
		tp, err := initTracerProvider(ctx, cfg.Telemetry.OTLPEndpoint, "seal-api")
		if err != nil {
			slog.Error("failed to init tracer provider", "error", err)
			os.Exit(1)
		}
		defer func() { _ = tp.Shutdown(context.Background()) }()
	}

	repo, err := internal.NewRepository(ctx, cfg.Database.ConnString())
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer repo.Close()

	queue, err := internal.NewQueue(ctx, cfg.Redis.Addr(), cfg.Redis.Password)
	if err != nil {
		slog.Error("failed to connect to redis", "error", err)
		os.Exit(1)
	}
	defer func() { _ = queue.Close() }()

	if len(os.Args) > 1 && os.Args[1] == "migrate" {
		slog.Info("running migrations")
		if err := internal.Migrate(ctx, repo.Pool()); err != nil {
			slog.Error("migration failed", "error", err)
			os.Exit(1)
		}
		slog.Info("migrations complete")
		return
	}

	handler := internal.NewHandler(repo, queue, cfg.DownloadBaseURL)
	router := internal.NewRouter(handler)

	// Background consumer: reads results from Redis and updates PostgreSQL
	go func() {
		tracer := otel.Tracer("seal-api")
		for {
			resultStr, err := queue.PopResult(ctx, 5*time.Second)
			if err != nil {
				if err == redis.Nil {
					continue
				}
				slog.Error("pop result from queue", "error", err)
				time.Sleep(time.Second)
				continue
			}

			var result struct {
				DocumentID  string `json:"document_id"`
				Status      string `json:"status"`
				S3Path      string `json:"s3_path"`
				Error       string `json:"error"`
				TraceParent string `json:"traceparent,omitempty"`
			}
			if err := json.Unmarshal([]byte(resultStr), &result); err != nil {
				slog.Error("unmarshal result", "result", resultStr, "error", err)
				continue
			}

			resultCtx := ctx
			if result.TraceParent != "" {
				propagator := otel.GetTextMapPropagator()
				carrier := propagation.MapCarrier{"traceparent": result.TraceParent}
				resultCtx = propagator.Extract(ctx, carrier)
			}

			resultCtx, span := tracer.Start(resultCtx, "PopResult")
			span.SetAttributes(
				attribute.String("document.id", result.DocumentID),
				attribute.String("result.status", result.Status),
			)

			docID, err := uuid.Parse(result.DocumentID)
			if err != nil {
				slog.Error("parse document ID from result", "document_id", result.DocumentID, "error", err)
				span.End()
				continue
			}

			if err := repo.UpdateStatus(resultCtx, docID, result.Status, result.S3Path, result.Error); err != nil {
				slog.Error("update document status from result", "document_id", docID, "error", err)
				span.RecordError(err)
			} else {
				slog.Info("document status updated from result",
					"document_id", docID,
					"status", result.Status,
					"s3_path", result.S3Path,
				)
				if result.Error != "" {
					slog.Warn("result contained error", "document_id", docID, "error", result.Error)
				}
			}
			span.End()
		}
	}()

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTP.Port),
		Handler:      otelhttp.NewHandler(router, "seal-api"),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("starting server", "port", cfg.HTTP.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down gracefully")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
}

func initTracerProvider(ctx context.Context, endpoint, serviceName string) (*sdktrace.TracerProvider, error) {
	host, insecure := parseOTLPEndpoint(endpoint)

	var opts []otlptracehttp.Option
	opts = append(opts, otlptracehttp.WithEndpoint(host))
	if insecure {
		opts = append(opts, otlptracehttp.WithInsecure())
	}
	exporter, err := otlptracehttp.New(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("create otlp exporter: %w", err)
	}

	res := resource.NewSchemaless(
		attribute.String("service.name", serviceName),
	)

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(
		propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{},
			propagation.Baggage{},
		),
	)

	return tp, nil
}

func parseOTLPEndpoint(raw string) (host string, insecure bool) {
	if strings.HasPrefix(raw, "http://") {
		return strings.TrimPrefix(raw, "http://"), true
	}
	if strings.HasPrefix(raw, "https://") {
		return strings.TrimPrefix(raw, "https://"), false
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return raw, true
	}
	return u.Host, u.Scheme == "http"
}

func setLogLevel(level string) {
	switch level {
	case "debug":
		slog.SetLogLoggerLevel(slog.LevelDebug)
	case "info":
		slog.SetLogLoggerLevel(slog.LevelInfo)
	case "warn":
		slog.SetLogLoggerLevel(slog.LevelWarn)
	case "error":
		slog.SetLogLoggerLevel(slog.LevelError)
	}
}
