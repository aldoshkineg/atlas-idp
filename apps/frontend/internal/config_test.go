package internal

import (
	"context"
	"os"
	"testing"
)

func TestLoadConfig_Defaults(t *testing.T) {
	cfg, err := LoadConfig(context.Background())
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if cfg.HTTP.Port != 8081 {
		t.Errorf("HTTP.Port = %d, want 8081", cfg.HTTP.Port)
	}
	if cfg.HTTP.LogLevel != "info" {
		t.Errorf("HTTP.LogLevel = %s, want info", cfg.HTTP.LogLevel)
	}
	if cfg.BackendAPIURL != "http://localhost:8080" {
		t.Errorf("BackendAPIURL = %s, want http://localhost:8080", cfg.BackendAPIURL)
	}
}

func TestLoadConfig_FromEnv(t *testing.T) {
	os.Setenv("HTTP_PORT", "9090")
	os.Setenv("BACKEND_API_URL", "http://api:8080")
	os.Setenv("LOG_LEVEL", "debug")
	defer func() {
		os.Unsetenv("HTTP_PORT")
		os.Unsetenv("BACKEND_API_URL")
		os.Unsetenv("LOG_LEVEL")
	}()

	cfg, err := LoadConfig(context.Background())
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if cfg.HTTP.Port != 9090 {
		t.Errorf("HTTP.Port = %d, want 9090", cfg.HTTP.Port)
	}
	if cfg.BackendAPIURL != "http://api:8080" {
		t.Errorf("BackendAPIURL = %s, want http://api:8080", cfg.BackendAPIURL)
	}
	if cfg.HTTP.LogLevel != "debug" {
		t.Errorf("HTTP.LogLevel = %s, want debug", cfg.HTTP.LogLevel)
	}
}