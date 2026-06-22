package internal

import (
	"context"
	"os"
	"testing"
)

func TestLoadConfigDefaults(t *testing.T) {
	t.Setenv("MINIO_ACCESS_KEY", "testkey")
	t.Setenv("MINIO_SECRET_KEY", "testsecret")

	cfg, err := LoadConfig(context.Background())
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}

	if cfg.Worker.PollInterval != 1000 {
		t.Errorf("Worker.PollInterval = %d, want 1000", cfg.Worker.PollInterval)
	}
}

func TestConfigValidation(t *testing.T) {
	os.Clearenv()
	_, err := LoadConfig(context.Background())
	if err == nil {
		t.Error("expected error when required env vars are missing")
	}
}
