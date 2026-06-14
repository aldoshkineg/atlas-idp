package internal

import (
	"testing"
)

func TestQueueKeys(t *testing.T) {
	if pendingQueue != "text2pdf:jobs" {
		t.Errorf("pendingQueue = %s", pendingQueue)
	}
	if processingQueue != "text2pdf:processing" {
		t.Errorf("processingQueue = %s", processingQueue)
	}
	if dlqQueue != "text2pdf:dlq" {
		t.Errorf("dlqQueue = %s", dlqQueue)
	}
}
