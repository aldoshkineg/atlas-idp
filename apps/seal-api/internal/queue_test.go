package internal

import (
	"testing"
)

func TestQueueKeys(t *testing.T) {
	if QueueKey != "seal:jobs" {
		t.Errorf("QueueKey = %s, want seal:jobs", QueueKey)
	}
	if ResultsQueueKey != "seal:results" {
		t.Errorf("ResultsQueueKey = %s, want seal:results", ResultsQueueKey)
	}
}
