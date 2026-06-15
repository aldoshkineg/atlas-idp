package internal

import (
	"testing"
)

func TestQueueKeys(t *testing.T) {
	if pendingQueue != "seal:jobs" {
		t.Errorf("pendingQueue = %s", pendingQueue)
	}
	if processingQueue != "seal:processing" {
		t.Errorf("processingQueue = %s", processingQueue)
	}
	if resultsQueue != "seal:results" {
		t.Errorf("resultsQueue = %s", resultsQueue)
	}
	if dlqQueue != "seal:dlq" {
		t.Errorf("dlqQueue = %s", dlqQueue)
	}
}
