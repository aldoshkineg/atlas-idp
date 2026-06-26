package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aldoshkineg/atlas-idp/apps/seal-worker/internal"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	cfg, err := internal.LoadConfig(ctx)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	if cfg.Telemetry.OTLPEndpoint != "" {
		tp, err := initTracerProvider(ctx, cfg.Telemetry.OTLPEndpoint, "seal-worker")
		if err != nil {
			slog.Error("failed to init tracer provider", "error", err)
			os.Exit(1)
		}
		defer func() { _ = tp.Shutdown(context.Background()) }()
	}

	redisClient := redis.NewClient(&redis.Options{
		Addr:         cfg.Redis.Addr(),
		Password:     cfg.Redis.Password,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 5 * time.Second,
	})
	defer func() { _ = redisClient.Close() }()
	redisClient.AddHook(&redisTracer{})

	storage, err := internal.NewStorage(ctx, cfg.Minio)
	if err != nil {
		slog.Error("failed to connect to minio", "error", err)
		os.Exit(1)
	}

	var signer *internal.Signer
	if _, err := os.Stat(cfg.Crypto.CertPath); err == nil {
		signer, err = internal.NewSigner(ctx, cfg.Crypto.CertPath, cfg.Crypto.KeyPath)
		if err != nil {
			slog.Error("failed to initialize signer", "error", err)
			os.Exit(1)
		}
	} else {
		slog.Warn("PDF signing disabled: cert not found", "path", cfg.Crypto.CertPath)
	}

	worker := internal.NewWorker(redisClient, storage, signer,
		time.Duration(cfg.Worker.PollInterval)*time.Millisecond)

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:    ":9090",
		Handler: mux,
	}

	go func() {
		slog.Info("starting metrics server", "port", 9090)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("metrics server error", "error", err)
		}
	}()

	go func() {
		if err := worker.Run(ctx); err != nil && err != context.Canceled {
			slog.Error("worker error", "error", err)
			cancel()
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down gracefully")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	_ = srv.Shutdown(shutdownCtx)
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
	return raw, true
}

type redisTracer struct{}

func (h *redisTracer) DialHook(next redis.DialHook) redis.DialHook {
	return next
}

func (h *redisTracer) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		ctx, span := otel.Tracer("seal-worker").Start(ctx, "REDIS "+cmd.Name(),
			trace.WithAttributes(attribute.String("redis.cmd", cmd.String())))
		defer span.End()
		err := next(ctx, cmd)
		if err != nil {
			span.RecordError(err)
		}
		return err
	}
}

func (h *redisTracer) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		ctx, span := otel.Tracer("seal-worker").Start(ctx, "REDIS pipeline",
			trace.WithAttributes(attribute.Int("redis.pipeline_size", len(cmds))))
		defer span.End()
		return next(ctx, cmds)
	}
}
