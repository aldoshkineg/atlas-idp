package internal

import (
	"context"
	"os"
	"testing"
)

func TestLoadConfigDefaults(t *testing.T) {
	os.Setenv("POSTGRES_PASSWORD", "testpass")
	defer func() {
		os.Unsetenv("POSTGRES_PASSWORD")
	}()

	cfg, err := LoadConfig(context.Background())
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}

	if cfg.HTTP.Port != 8080 {
		t.Errorf("HTTP.Port = %d, want 8080", cfg.HTTP.Port)
	}
	if cfg.Database.Host != "localhost" {
		t.Errorf("Database.Host = %s, want localhost", cfg.Database.Host)
	}
	if cfg.Database.User != "text2pdf" {
		t.Errorf("Database.User = %s, want text2pdf", cfg.Database.User)
	}
}

func TestConfigValidation(t *testing.T) {
	os.Clearenv()
	_, err := LoadConfig(context.Background())
	if err == nil {
		t.Error("expected error when required env vars are missing")
	}
}

func TestConnString(t *testing.T) {
	cfg := DatabaseConfig{
		Host:     "myhost",
		Port:     5432,
		User:     "user",
		Password: "pass",
		DBName:   "db",
	}
	want := "postgres://user:pass@myhost:5432/db?sslmode=disable"
	if got := cfg.ConnString(); got != want {
		t.Errorf("ConnString() = %s, want %s", got, want)
	}
}
