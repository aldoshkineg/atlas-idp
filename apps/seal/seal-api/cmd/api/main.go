package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aldoshkineg/atlas-idp/apps/seal-api/internal"
	"github.com/google/uuid"
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

	setLogLevel(cfg.HTTP.LogLevel)

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

			slog.Debug("result popped from queue", "result", resultStr)

			var result struct {
				DocumentID string `json:"document_id"`
				Status     string `json:"status"`
				S3Path     string `json:"s3_path"`
				Error      string `json:"error"`
			}
			if err := json.Unmarshal([]byte(resultStr), &result); err != nil {
				slog.Error("unmarshal result", "result", resultStr, "error", err)
				continue
			}

			docID, err := uuid.Parse(result.DocumentID)
			if err != nil {
				slog.Error("parse document ID from result", "document_id", result.DocumentID, "error", err)
				continue
			}

			if err := repo.UpdateStatus(ctx, docID, result.Status, result.S3Path, result.Error); err != nil {
				slog.Error("update document status from result", "document_id", docID, "error", err)
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
		}
	}()

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTP.Port),
		Handler:      router,
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
