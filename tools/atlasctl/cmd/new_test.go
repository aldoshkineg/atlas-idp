package cmd

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func resetNewFlags() {
	newCmdFlags = newFlags{}
}

func TestNewCmd_NoGroup(t *testing.T) {
	resetNewFlags()
	rootCmd.SetArgs([]string{"new", "myapp", "--repo", "https://example.com/repo.git"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing --group")
	}
	if !strings.Contains(err.Error(), "--group is required") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestNewCmd_NoRepo(t *testing.T) {
	resetNewFlags()
	rootCmd.SetArgs([]string{"new", "myapp", "--group", "testgroup"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing --repo")
	}
	if !strings.Contains(err.Error(), "--repo is required") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestNewCmd_NoApp(t *testing.T) {
	resetNewFlags()
	rootCmd.SetArgs([]string{"new", "--group", "testgroup", "--repo", "https://example.com/repo.git"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing app name")
	}
}

func TestNewCmd_FullScaffold(t *testing.T) {
	resetNewFlags()
	tmpDir := t.TempDir()
	origDir, _ := os.Getwd()
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	repoRoot := filepath.Dir(filepath.Dir(origDir))
	if _, err := os.Stat(filepath.Join(repoRoot, "templates")); os.IsNotExist(err) {
		t.Skip("templates directory not found")
	}

	InitTemplateFS()

	rootCmd.SetArgs([]string{"new", "testapp", "--group", "testgroup", "--repo", "https://github.com/test/test.git", "-y"})
	err := rootCmd.Execute()
	if err != nil {
		t.Fatalf("new command failed: %v", err)
	}

	expectedFiles := []string{
		"workloads/testgroup/testapp/app.yaml",
		"workloads/testgroup/testapp/secrets.yaml",
		"workloads/testgroup/testapp/README.md",
		"workloads/testgroup/testapp/.secret-seed",
		"workloads/testgroup/testapp/vault/policy.hcl",
		"workloads/testgroup/testapp/vault/k8s-auth-role.yaml",
		"workloads/testgroup/testapp/vault/seed-mapping.conf",
		"workloads/testgroup/testapp/monitoring/pod-monitor.yaml",
		"workloads/testgroup/testapp/monitoring/prometheus-rule.yaml",
		"workloads/testgroup/testapp/infra/gateway.yaml",
		"workloads/testgroup/testapp/infra/network-policy.yaml",
		"workloads/testgroup/testapp/infra/resource-quota.yaml",
		"workloads/testgroup/testapp/infra/limit-range.yaml",
		"workloads/testgroup/testapp/infra/keda-scaledobject.yaml",
		"workloads/testgroup/testapp/infra/ccnp-ingress.yaml",
	}

	for _, f := range expectedFiles {
		path := filepath.Join(tmpDir, f)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			t.Errorf("expected file not created: %s", f)
		}
	}
}

func TestNewCmd_AlreadyExists(t *testing.T) {
	resetNewFlags()
	tmpDir := t.TempDir()
	origDir, _ := os.Getwd()
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	repoRoot := filepath.Dir(filepath.Dir(origDir))
	if _, err := os.Stat(filepath.Join(repoRoot, "templates")); os.IsNotExist(err) {
		t.Skip("templates directory not found")
	}

	InitTemplateFS()

	os.MkdirAll("workloads/testgroup/testapp", 0755)

	rootCmd.SetArgs([]string{"new", "testapp", "--group", "testgroup", "--repo", "https://github.com/test/test.git", "-y"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for existing workload")
	}
	if !strings.Contains(err.Error(), "already exists") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestNewCmd_NamespaceDefault(t *testing.T) {
	resetNewFlags()
	tmpDir := t.TempDir()
	origDir, _ := os.Getwd()
	os.Chdir(tmpDir)
	defer os.Chdir(origDir)

	repoRoot := filepath.Dir(filepath.Dir(origDir))
	if _, err := os.Stat(filepath.Join(repoRoot, "templates")); os.IsNotExist(err) {
		t.Skip("templates not found")
	}

	InitTemplateFS()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"new", "myapp", "--group", "mygroup", "--repo", "https://example.com/repo.git", "-y"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("new command failed: %v", err)
	}

	data, _ := os.ReadFile("workloads/mygroup/myapp/app.yaml")
	content := string(data)
	if !strings.Contains(content, "namespace: mygroup-myapp") {
		t.Errorf("expected namespace 'mygroup-myapp' in app.yaml, got:\n%s", content)
	}
}

func TestRootCmd_Version(t *testing.T) {
	resetNewFlags()
	rootCmd.SetArgs([]string{"--version"})
	err := rootCmd.Execute()
	if err != nil {
		t.Errorf("--version should not error: %v", err)
	}
}

func TestRootCmd_Help(t *testing.T) {
	resetNewFlags()
	rootCmd.SetArgs([]string{"--help"})
	err := rootCmd.Execute()
	if err != nil {
		t.Errorf("--help should not error: %v", err)
	}
}

func suppressOutput() func() {
	oldOut := os.Stdout
	oldErr := os.Stderr
	r, w, _ := os.Pipe()
	os.Stdout = w
	os.Stderr = w
	return func() {
		w.Close()
		os.Stdout = oldOut
		os.Stderr = oldErr
		io.Copy(io.Discard, r)
	}
}
