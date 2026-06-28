package gitops

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

func TestWorkloadRef(t *testing.T) {
	ref := WorkloadRef{Group: "testgroup", App: "testapp"}
	if ref.String() != "testgroup/testapp" {
		t.Errorf("String() = %q, want %q", ref.String(), "testgroup/testapp")
	}
}

func TestResolvePaths(t *testing.T) {
	gc := &config.GitopsConfig{
		WorkloadsDir:     "gitops/workloads",
		GatewayFile:      "gitops/platform-kind/layers/networking/values/gateway-resources/gateway.yaml",
		GatewayRoutesDir: "gitops/platform-kind/layers/networking/values/gateway-routes",
	}
	p := ResolvePaths(WorkloadRef{Group: "g", App: "a"}, gc, "workloads")
	if !strings.HasSuffix(p.WorkloadDir, "workloads/g/a") {
		t.Errorf("WorkloadDir = %q", p.WorkloadDir)
	}
	if !strings.HasSuffix(p.GitopsFile, "gitops/workloads/g/a.yaml") {
		t.Errorf("GitopsFile = %q", p.GitopsFile)
	}
	if !strings.Contains(p.GatewayFile, "gateway-resources/gateway.yaml") {
		t.Errorf("GatewayFile = %q", p.GatewayFile)
	}
}

func TestCopyWorkloadManifest(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.yaml")
	dst := filepath.Join(dir, "sub", "dst.yaml")
	os.WriteFile(src, []byte("content: test"), 0644)

	if err := CopyWorkloadManifest(src, dst); err != nil {
		t.Fatalf("CopyWorkloadManifest: %v", err)
	}

	data, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "content: test" {
		t.Errorf("unexpected content: %s", data)
	}
}

func TestSyncResources(t *testing.T) {
	dir := t.TempDir()
	workloadDir := filepath.Join(dir, "workload")
	resourcesDir := filepath.Join(dir, "resources")

	os.MkdirAll(filepath.Join(workloadDir, "infra"), 0755)
	os.WriteFile(filepath.Join(workloadDir, "app.yaml"), []byte("app"), 0644)
	os.WriteFile(filepath.Join(workloadDir, "secrets.yaml"), []byte("secrets"), 0644)
	os.WriteFile(filepath.Join(workloadDir, ".secret-seed"), []byte("seed"), 0644)
	os.WriteFile(filepath.Join(workloadDir, "infra", "gateway.yaml"), []byte("gw"), 0644)
	os.WriteFile(filepath.Join(workloadDir, "infra", "network-policy.yaml"), []byte("np"), 0644)

	if err := SyncResources(workloadDir, resourcesDir); err != nil {
		t.Fatalf("SyncResources: %v", err)
	}

	checkExists := func(path string, shouldExist bool) {
		_, err := os.Stat(filepath.Join(dir, path))
		if shouldExist && err != nil {
			t.Errorf("expected %s to exist", path)
		}
		if !shouldExist && err == nil {
			t.Errorf("expected %s to NOT exist", path)
		}
	}

	checkExists("resources/secrets.yaml", true)
	checkExists("resources/app.yaml", false)
	checkExists("resources/.secret-seed", false)
	checkExists("resources/infra/gateway.yaml", false)
	checkExists("resources/infra/network-policy.yaml", true)
}

func TestRemoveAll(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "a", "b", "c"), 0755)
	os.WriteFile(filepath.Join(dir, "a", "b", "f.txt"), []byte("x"), 0644)

	if err := RemoveAll(filepath.Join(dir, "a")); err != nil {
		t.Fatalf("RemoveAll: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "a")); !os.IsNotExist(err) {
		t.Errorf("expected a/ to be removed")
	}
}

func TestRemoveEmptyDir(t *testing.T) {
	dir := t.TempDir()
	emptyDir := filepath.Join(dir, "empty")
	nonEmptyDir := filepath.Join(dir, "nonempty")

	os.MkdirAll(emptyDir, 0755)
	os.MkdirAll(nonEmptyDir, 0755)
	os.WriteFile(filepath.Join(nonEmptyDir, "f.txt"), []byte("x"), 0644)

	RemoveEmptyDir(emptyDir)
	if _, err := os.Stat(emptyDir); !os.IsNotExist(err) {
		t.Errorf("empty dir should be removed")
	}

	RemoveEmptyDir(nonEmptyDir)
	if _, err := os.Stat(nonEmptyDir); os.IsNotExist(err) {
		t.Errorf("non-empty dir should NOT be removed")
	}
}

func TestApplyGatewayListener_Add(t *testing.T) {
	dir := t.TempDir()
	gwPath := filepath.Join(dir, "gateway.yaml")
	os.WriteFile(gwPath, []byte("spec:\n  listeners: []\n"), 0644)

	msg, err := ApplyGatewayListener(gwPath, GatewayListenerChange{
		App:      "myapp",
		Hostname: "myapp.atlas",
		CertName: "myapp-cert",
		Add:      true,
	})
	if err != nil {
		t.Fatalf("ApplyGatewayListener: %v", err)
	}
	if !strings.Contains(msg, "Added") {
		t.Errorf("expected 'Added' in message, got: %s", msg)
	}

	msg, err = ApplyGatewayListener(gwPath, GatewayListenerChange{
		App:      "myapp",
		Hostname: "myapp.atlas",
		Add:      true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(msg, "already exists") {
		t.Errorf("expected 'already exists' for duplicate add, got: %s", msg)
	}
}

func TestApplyGatewayListener_Remove(t *testing.T) {
	dir := t.TempDir()
	gwPath := filepath.Join(dir, "gateway.yaml")
	os.WriteFile(gwPath, []byte("spec:\n  listeners: []\n"), 0644)

	msg, err := ApplyGatewayListener(gwPath, GatewayListenerChange{
		App:      "nonexistent",
		Hostname: "x.atlas",
		Add:      false,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(msg, "not found") {
		t.Errorf("expected 'not found' for remove of nonexistent, got: %s", msg)
	}
}
