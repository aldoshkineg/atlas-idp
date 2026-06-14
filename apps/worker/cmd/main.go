package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aldoshkineg/atlas-idp/apps/worker/internal"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	cfg, err := internal.LoadConfig(ctx)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	redisClient := redis.NewClient(&redis.Options{
		Addr:         cfg.Redis.Addr(),
		Password:     cfg.Redis.Password,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 5 * time.Second,
	})
	defer func() { _ = redisClient.Close() }()

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
