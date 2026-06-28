package vault

import (
	"testing"
)

func TestNew(t *testing.T) {
	c := New()
	if c == nil {
		t.Fatal("New() returned nil")
	}
}

func TestNew_UsesKubectlByDefault(t *testing.T) {
	c := New()
	if c.kubectlPath != "kubectl" {
		t.Errorf("expected kubectl path, got %q", c.kubectlPath)
	}
}
