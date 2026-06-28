package argocd

import (
	"os/exec"
	"testing"
)

func TestNew(t *testing.T) {
	c := New()
	if c == nil {
		t.Fatal("New() returned nil")
	}
}

func TestNew_UsesArgocdByDefault(t *testing.T) {
	c := New()
	if c.cliPath != "argocd" {
		t.Errorf("expected argocd path, got %q", c.cliPath)
	}
}

func TestAvailable_ReturnsFalseWhenNotFound(t *testing.T) {
	c := &Client{cliPath: "nonexistent-argocd-binary"}
	if c.Available() {
		t.Error("Available() should be false when binary doesn't exist")
	}
}

func TestGetApp_ErrorWhenNotInstalled(t *testing.T) {
	c := &Client{cliPath: "nonexistent-argocd-binary"}
	_, err := c.GetApp("test-app")
	if err == nil {
		t.Error("expected error when argocd binary not found")
	}
}

func TestListApps_ErrorWhenNotInstalled(t *testing.T) {
	c := &Client{cliPath: "nonexistent-argocd-binary"}
	_, err := c.ListApps()
	if err == nil {
		t.Error("expected error when argocd binary not found")
	}
}

func TestAvailable_UsesExecLookPath(t *testing.T) {
	path, err := exec.LookPath("kubectl")
	c := &Client{cliPath: "kubectl"}
	available := c.Available()
	if err == nil && !available {
		t.Errorf("Available() should be true for %s", path)
	}
	if err != nil && available {
		t.Errorf("Available() should be false for missing binary")
	}
}
