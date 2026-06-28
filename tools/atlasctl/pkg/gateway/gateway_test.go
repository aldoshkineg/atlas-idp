package gateway

import (
	"path/filepath"
	"testing"
)

func TestGateway_AddListener(t *testing.T) {
	gw := &Gateway{}
	gw.AddListener("https-myapp", "myapp.atlas", "myapp-cert")

	if !gw.HasListener("https-myapp") {
		t.Error("listener should exist after add")
	}
	if len(gw.Spec.Listeners) != 1 {
		t.Errorf("expected 1 listener, got %d", len(gw.Spec.Listeners))
	}

	l := gw.Spec.Listeners[0]
	if l.Port != 443 {
		t.Errorf("expected port 443, got %d", l.Port)
	}
	if l.Protocol != "HTTPS" {
		t.Errorf("expected HTTPS protocol, got %s", l.Protocol)
	}
	if l.Hostname != "myapp.atlas" {
		t.Errorf("expected hostname 'myapp.atlas', got %s", l.Hostname)
	}
	if l.TLS.Mode != "Terminate" {
		t.Errorf("expected TLS mode Terminate, got %s", l.TLS.Mode)
	}
	if len(l.TLS.CertificateRefs) != 1 || l.TLS.CertificateRefs[0].Name != "myapp-cert" {
		t.Errorf("expected cert ref 'myapp-cert', got %v", l.TLS.CertificateRefs)
	}
}

func TestGateway_RemoveListener(t *testing.T) {
	gw := &Gateway{}
	gw.AddListener("https-a", "a.atlas", "a-cert")
	gw.AddListener("https-b", "b.atlas", "b-cert")
	gw.AddListener("https-c", "c.atlas", "c-cert")

	if !gw.RemoveListener("https-b") {
		t.Error("RemoveListener should return true when removed")
	}
	if len(gw.Spec.Listeners) != 2 {
		t.Errorf("expected 2 listeners after removal, got %d", len(gw.Spec.Listeners))
	}
	if gw.HasListener("https-b") {
		t.Error("listener https-b should be removed")
	}
}

func TestGateway_RemoveNonExistent(t *testing.T) {
	gw := &Gateway{}
	if gw.RemoveListener("nonexistent") {
		t.Error("RemoveListener should return false for non-existent")
	}
}

func TestGateway_HasListener(t *testing.T) {
	gw := &Gateway{}
	gw.AddListener("https-app", "app.atlas", "app-cert")

	tests := []struct {
		name     string
		expected bool
	}{
		{"https-app", true},
		{"https-other", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := gw.HasListener(tt.name); got != tt.expected {
				t.Errorf("HasListener(%q) = %v, want %v", tt.name, got, tt.expected)
			}
		})
	}
}

func TestGateway_LoadSave(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "gateway.yaml")

	gw := &Gateway{}
	gw.AddListener("https-app", "app.atlas", "app-cert")

	if err := SaveGateway(path, gw); err != nil {
		t.Fatalf("SaveGateway: %v", err)
	}

	loaded, err := LoadGateway(path)
	if err != nil {
		t.Fatalf("LoadGateway: %v", err)
	}

	if !loaded.HasListener("https-app") {
		t.Error("loaded gateway should have https-app listener")
	}
}

func TestGateway_LoadFileNotFound(t *testing.T) {
	_, err := LoadGateway("/nonexistent/path")
	if err == nil {
		t.Error("expected error for nonexistent file")
	}
}
