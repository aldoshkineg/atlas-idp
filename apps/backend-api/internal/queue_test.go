package internal

import (
	"testing"
)

func TestQueueKeys(t *testing.T) {
	if QueueKey != "text2pdf:jobs" {
		t.Errorf("QueueKey = %s, want text2pdf:jobs", QueueKey)
	}
	if ResultsQueueKey != "text2pdf:results" {
		t.Errorf("ResultsQueueKey = %s, want text2pdf:results", ResultsQueueKey)
	}
}
