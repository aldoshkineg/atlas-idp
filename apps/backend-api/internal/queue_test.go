package internal

import (
	"testing"
)

func TestQueueKey(t *testing.T) {
	if QueueKey != "text2pdf:jobs" {
		t.Errorf("QueueKey = %s, want text2pdf:jobs", QueueKey)
	}
}
