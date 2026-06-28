package gateway

import (
	"os"
	"path/filepath"
	"testing"
)

func writeTestGateway(t *testing.T, names []string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "gateway.yaml")

	y := `apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gateway
  namespace: nginx-gateway-fabric
spec:
  gatewayClassName: nginx
  listeners:
`
	for _, n := range names {
		y += `    - name: ` + n + `
      port: 443
      protocol: HTTPS
      hostname: "` + n + `.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: ` + n + `-cert
`
	}

	if err := os.WriteFile(path, []byte(y), 0644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRemoveListener(t *testing.T) {
	path := writeTestGateway(t, []string{"https-a", "https-seal", "https-c"})

	removed, err := RemoveListenerFromFile(path, "seal")
	if err != nil {
		t.Fatal(err)
	}
	if !removed {
		t.Fatal("expected removed=true")
	}

	if HasListenerInFile(path, "seal") {
		t.Error("https-seal should be removed")
	}
	if !HasListenerInFile(path, "a") || !HasListenerInFile(path, "c") {
		t.Error("other listeners should remain")
	}
}

func TestRemoveNonExistent(t *testing.T) {
	path := writeTestGateway(t, []string{"https-a", "https-b"})

	removed, err := RemoveListenerFromFile(path, "nonexistent")
	if err != nil {
		t.Fatal(err)
	}
	if removed {
		t.Error("should return false for non-existent listener")
	}
}

func TestHasListener(t *testing.T) {
	path := writeTestGateway(t, []string{"https-seal", "https-grafana"})

	tests := []struct {
		app      string
		expected bool
	}{
		{"seal", true},
		{"grafana", true},
		{"vault", false},
	}

	for _, tt := range tests {
		t.Run(tt.app, func(t *testing.T) {
			if got := HasListenerInFile(path, tt.app); got != tt.expected {
				t.Errorf("HasListenerInFile(%q) = %v, want %v", tt.app, got, tt.expected)
			}
		})
	}
}

func TestAppendListener(t *testing.T) {
	path := writeTestGateway(t, []string{"https-a", "https-b"})

	if err := AppendListenerToFile(path, ListenerData{Name: "https-c", Port: 443, Hostname: "c.atlas", CertName: "c-cert"}); err != nil {
		t.Fatal(err)
	}

	if !HasListenerInFile(path, "c") {
		t.Error("https-c should exist after append")
	}
	if !HasListenerInFile(path, "a") || !HasListenerInFile(path, "b") {
		t.Error("original listeners should remain")
	}
}

func TestRemoveLastListener(t *testing.T) {
	path := writeTestGateway(t, []string{"https-onlyone"})

	removed, err := RemoveListenerFromFile(path, "onlyone")
	if err != nil {
		t.Fatal(err)
	}
	if !removed {
		t.Fatal("expected removed=true")
	}

	if HasListenerInFile(path, "onlyone") {
		t.Error("should be removed")
	}
}

func TestRemoveFirstListener(t *testing.T) {
	path := writeTestGateway(t, []string{"https-first", "https-second", "https-third"})

	removed, err := RemoveListenerFromFile(path, "first")
	if err != nil {
		t.Fatal(err)
	}
	if !removed {
		t.Fatal("expected removed=true")
	}

	if HasListenerInFile(path, "first") {
		t.Error("https-first should be removed")
	}
	if !HasListenerInFile(path, "second") || !HasListenerInFile(path, "third") {
		t.Error("other listeners should remain")
	}
}

func TestRenderListener(t *testing.T) {
	got, err := RenderListener(ListenerData{Name: "https-test", Port: 443, Hostname: "test.atlas", CertName: "test-cert"})
	if err != nil {
		t.Fatal(err)
	}

	want := `    - name: https-test
      port: 443
      protocol: HTTPS
      hostname: "test.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: test-cert
`
	if got != want {
		t.Errorf("rendered template mismatch:\ngot:\n%s\nwant:\n%s", got, want)
	}
}
