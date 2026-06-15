//go:build integration

package internal

import (
	"testing"
)

func TestWorkerIntegration(t *testing.T) {
	t.Skip("requires real redis, minio")
}
