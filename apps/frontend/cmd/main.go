package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aldoshkineg/atlas-idp/apps/frontend/internal"
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

	router := internal.NewRouter(cfg.BackendAPIURL)

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTP.Port),
		Handler:      router,
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
