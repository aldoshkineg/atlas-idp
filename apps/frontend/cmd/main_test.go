package main

import (
	"os"
	"testing"
)

func TestSetLogLevel(t *testing.T) {
	tests := []struct {
		level string
		valid bool
	}{
		{"debug", true},
		{"info", true},
		{"warn", true},
		{"error", true},
		{"invalid", false},
	}
	for _, tt := range tests {
		t.Run(tt.level, func(t *testing.T) {
			func() {
				defer func() {
					if r := recover(); r != nil {
						t.Errorf("setLogLevel panicked for %s", tt.level)
					}
				}()
				setLogLevel(tt.level)
			}()
		})
	}
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}