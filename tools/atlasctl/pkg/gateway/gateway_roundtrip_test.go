package gateway

import (
	"os"
	"testing"
)

func TestMarshalRoundTrip(t *testing.T) {
	path := t.TempDir() + "/gw.yaml"

	input := `apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gateway
  namespace: nginx-gateway-fabric
spec:
  gatewayClassName: nginx
  listeners:
    - name: https-app
      port: 443
      protocol: HTTPS
      hostname: "app.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: app-cert
    - name: https-other
      port: 443
      protocol: HTTPS
      hostname: "other.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: other-cert
`
	if err := os.WriteFile(path, []byte(input), 0644); err != nil {
		t.Fatal(err)
	}

	if !HasListenerInFile(path, "app") || !HasListenerInFile(path, "other") {
		t.Error("missing listeners after load")
	}

	removed, err := RemoveListenerFromFile(path, "app")
	if err != nil {
		t.Fatal(err)
	}
	if !removed {
		t.Fatal("expected removed=true")
	}

	if HasListenerInFile(path, "app") {
		t.Error("https-app should be removed")
	}
	if !HasListenerInFile(path, "other") {
		t.Error("https-other should remain")
	}
}

func TestGateway_RemoveAll(t *testing.T) {
	path := t.TempDir() + "/gw.yaml"

	input := `spec:
  listeners:
    - name: https-a
      port: 443
      protocol: HTTPS
      hostname: "a.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: a-cert
    - name: https-b
      port: 443
      protocol: HTTPS
      hostname: "b.atlas"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: b-cert
`
	if err := os.WriteFile(path, []byte(input), 0644); err != nil {
		t.Fatal(err)
	}

	RemoveListenerFromFile(path, "a")
	RemoveListenerFromFile(path, "b")

	if HasListenerInFile(path, "a") || HasListenerInFile(path, "b") {
		t.Error("all listeners should be removed")
	}
}

func TestGateway_AppendToNonExistent(t *testing.T) {
	path := t.TempDir() + "/empty.yaml"
	if err := os.WriteFile(path, []byte("spec:\n  listeners: []\n"), 0644); err != nil {
		t.Fatal(err)
	}

	if err := AppendListenerToFile(path, ListenerData{Name: "https-test", Port: 443, Hostname: "test.atlas", CertName: "test-cert"}); err != nil {
		t.Fatal(err)
	}

	if !HasListenerInFile(path, "test") {
		t.Error("listener should be added")
	}
}
