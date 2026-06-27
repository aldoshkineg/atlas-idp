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

	"github.com/aldoshkineg/atlas-idp/apps/seal-ui/internal"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
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

	setLogLevel(cfg.HTTP.LogLevel)
	initLogger(cfg.HTTP.LogFormat)

	if cfg.Telemetry.OTLPEndpoint != "" {
		tp, err := initTracerProvider(ctx, cfg.Telemetry.OTLPEndpoint, "seal-ui")
		if err != nil {
			slog.Error("failed to init tracer provider", "error", err)
			os.Exit(1)
		}
		defer func() { _ = tp.Shutdown(context.Background()) }()
	}

	router := internal.NewRouter(cfg.BackendAPIURL)

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTP.Port),
		Handler:      otelhttp.NewHandler(router, "seal-ui"),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("starting frontend server", "port", cfg.HTTP.Port)
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
	return raw, true
}

func initLogger(format string) {
	if format != "json" {
		return
	}

	var level slog.Level
	switch strings.ToLower(os.Getenv("LOG_LEVEL")) {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}

	slog.SetDefault(slog.New(&traceHandler{
		Handler: slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}),
	}))
}

type traceHandler struct {
	slog.Handler
}

func (h *traceHandler) Handle(ctx context.Context, r slog.Record) error {
	if span := trace.SpanFromContext(ctx); span.IsRecording() {
		sc := span.SpanContext()
		r.AddAttrs(slog.String("trace_id", sc.TraceID().String()))
		r.AddAttrs(slog.String("span_id", sc.SpanID().String()))
	}
	return h.Handler.Handle(ctx, r)
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
