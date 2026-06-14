//go:build integration

package internal

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestIntegrationFullFlow(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	ctx := context.Background()

	os.Setenv("POSTGRES_PASSWORD", "text2pdf")
	os.Setenv("MINIO_ACCESS_KEY", "minioadmin")
	os.Setenv("MINIO_SECRET_KEY", "minioadminpassword")
	defer func() {
		os.Unsetenv("POSTGRES_PASSWORD")
		os.Unsetenv("MINIO_ACCESS_KEY")
		os.Unsetenv("MINIO_SECRET_KEY")
	}()

	cfg, err := LoadConfig(ctx)
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}

	repo, err := NewRepository(ctx, cfg.Database.ConnString())
	if err != nil {
		t.Fatalf("NewRepository() error = %v", err)
	}
	defer repo.Close()

	if err := Migrate(ctx, repo.Pool()); err != nil {
		t.Fatalf("Migrate() error = %v", err)
	}

	queue, err := NewQueue(ctx, cfg.Redis.Addr(), cfg.Redis.Password)
	if err != nil {
		t.Fatalf("NewQueue() error = %v", err)
	}
	defer queue.Close()

	handler := NewHandler(repo, queue, cfg.Minio)
	router := NewRouter(handler)

	t.Run("healthz", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("status = %d", rec.Code)
		}
	})
}
