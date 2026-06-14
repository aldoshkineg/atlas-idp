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
	if resultsQueue != "text2pdf:results" {
		t.Errorf("resultsQueue = %s", resultsQueue)
	}
	if dlqQueue != "text2pdf:dlq" {
		t.Errorf("dlqQueue = %s", dlqQueue)
	}
}
