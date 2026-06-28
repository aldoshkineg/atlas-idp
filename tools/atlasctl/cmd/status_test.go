package cmd

import (
	"os"
	"strings"
	"testing"
)

func resetStatusFlags() {
	statusCmdFlags = statusFlags{}
}

func resetListFlags() {
	listCmdFlags = listFlags{}
}

func resetLogsFlags() {
	logsCmdFlags = logsFlags{}
}

func resetBackupFlags() {
	backupCmdFlags = backupFlags{}
}

func TestStatusCmd_NoArg(t *testing.T) {
	resetStatusFlags()
	rootCmd.SetArgs([]string{"status"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing arg")
	}
}

func TestStatusCmd_InvalidFormat(t *testing.T) {
	resetStatusFlags()
	rootCmd.SetArgs([]string{"status", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestStatusCmd_WorkloadNotFound(t *testing.T) {
	resetStatusFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"status", "missing/workload"})
	err := rootCmd.Execute()
	restore()

	if err == nil || !strings.Contains(err.Error(), "workload not found") {
		t.Errorf("expected 'workload not found', got %v", err)
	}
}

func TestStatusCmd_PlainOutput(t *testing.T) {
	resetStatusFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)
	os.WriteFile("workloads/testgroup/testapp/app.yaml",
		[]byte("apiVersion: argoproj.io/v1alpha1\nkind: Application\nspec:\n  destination:\n    namespace: my-ns\n"), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"status", "testgroup/testapp"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("status failed: %v", err)
	}
}

func TestListCmd_NoWorkloads(t *testing.T) {
	resetListFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"list"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("list with no workloads failed: %v", err)
	}
}

func TestListCmd_WithWorkloads(t *testing.T) {
	resetListFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)
	os.WriteFile("workloads/testgroup/testapp/app.yaml",
		[]byte("apiVersion: argoproj.io/v1alpha1\nkind: Application\n"), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"list"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("list with workloads failed: %v", err)
	}
}

func TestListCmd_JSON(t *testing.T) {
	resetListFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)
	os.WriteFile("workloads/testgroup/testapp/app.yaml",
		[]byte("apiVersion: argoproj.io/v1alpha1\nkind: Application\n"), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"list", "--json"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("list --json failed: %v", err)
	}
}

func TestLogsCmd_NoArg(t *testing.T) {
	resetLogsFlags()
	rootCmd.SetArgs([]string{"logs"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing arg")
	}
}

func TestLogsCmd_InvalidFormat(t *testing.T) {
	resetLogsFlags()
	rootCmd.SetArgs([]string{"logs", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestBackupCmd_NoArg(t *testing.T) {
	resetBackupFlags()
	rootCmd.SetArgs([]string{"backup"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing arg")
	}
}

func TestBackupCmd_InvalidFormat(t *testing.T) {
	resetBackupFlags()
	rootCmd.SetArgs([]string{"backup", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestBackupCmd_DryRun(t *testing.T) {
	resetBackupFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"backup", "testgroup/testapp", "--dry-run"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("backup dry-run failed: %v", err)
	}
}

func TestDetectFeatures_None(t *testing.T) {
	dir := t.TempDir()
	features := detectFeatures(dir)
	if len(features) != 0 {
		t.Errorf("expected no features, got %v", features)
	}
}

func TestDetectFeatures_Secrets(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(dir+"/.secret-seed", []byte("x"), 0644)
	features := detectFeatures(dir)
	if !contains(features, "secrets") {
		t.Errorf("expected 'secrets' feature, got %v", features)
	}
}

func TestDetectFeatures_Gateway(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(dir+"/infra", 0755)
	os.WriteFile(dir+"/infra/gateway.yaml", []byte("x"), 0644)
	features := detectFeatures(dir)
	if !contains(features, "gateway") {
		t.Errorf("expected 'gateway' feature, got %v", features)
	}
}

func TestDetectFeatures_Monitoring(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(dir+"/monitoring", 0755)
	os.WriteFile(dir+"/monitoring/prometheus-rule.yaml", []byte("x"), 0644)
	features := detectFeatures(dir)
	if !contains(features, "monitoring") {
		t.Errorf("expected 'monitoring' feature, got %v", features)
	}
}

func contains(slice []string, s string) bool {
	for _, v := range slice {
		if v == s {
			return true
		}
	}
	return false
}

func TestAnsiColors(t *testing.T) {
	if ansiGreen("ok") != "\033[0;32mok\033[0m" {
		t.Error("ansiGreen output mismatch")
	}
	if ansiYellow("ok") != "\033[0;33mok\033[0m" {
		t.Error("ansiYellow output mismatch")
	}
	if ansiRed("ok") != "\033[0;31mok\033[0m" {
		t.Error("ansiRed output mismatch")
	}
}
