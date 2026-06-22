package internal

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const (
	outputBucket = "seal-outputs"
	maxRetries   = 3
)

type Storage struct {
	client *minio.Client
}

func NewStorage(ctx context.Context, cfg MinioConfig) (*Storage, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("new minio client: %w", err)
	}

	if err := client.MakeBucket(ctx, outputBucket, minio.MakeBucketOptions{}); err != nil {
		exists, errExists := client.BucketExists(ctx, outputBucket)
		if errExists != nil || !exists {
			return nil, fmt.Errorf("ensure bucket %s: %w", outputBucket, err)
		}
	}

	return &Storage{client: client}, nil
}

func (s *Storage) Upload(ctx context.Context, objectKey string, data []byte) error {
	var lastErr error
	backoff := time.Second

	for i := range maxRetries {
		_, err := s.client.PutObject(ctx, outputBucket, objectKey,
			bytes.NewReader(data), int64(len(data)),
			minio.PutObjectOptions{ContentType: "application/pdf"},
		)
		if err == nil {
			return nil
		}
		lastErr = err
		slog.Warn("minio upload failed", "attempt", i+1, "error", err)
		time.Sleep(backoff * (1 << i))
	}

	return fmt.Errorf("upload failed after %d retries: %w", maxRetries, lastErr)
}
