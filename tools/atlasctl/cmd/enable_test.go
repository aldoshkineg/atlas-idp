package cmd

import (
	"os"
	"strings"
	"testing"
)

func resetEnableFlags() {
	enableCmdFlags = enableFlags{}
}

func resetDisableFlags() {
	disableCmdFlags = disableFlags{}
}

func resetDeleteFlags() {
	deleteCmdFlags = deleteFlags{}
}

func TestEnableCmd_InvalidFormat(t *testing.T) {
	resetEnableFlags()
	rootCmd.SetArgs([]string{"enable", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestEnableCmd_NoArg(t *testing.T) {
	resetEnableFlags()
	rootCmd.SetArgs([]string{"enable"})
	err := rootCmd.Execute()
	if err == nil {
		t.Error("expected error for missing arg")
	}
}

func TestEnableCmd_WorkloadNotFound(t *testing.T) {
	resetEnableFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"enable", "missing/workload"})
	err := rootCmd.Execute()
	restore()

	if err == nil || !strings.Contains(err.Error(), "workload not found") {
		t.Errorf("expected 'workload not found', got %v", err)
	}
}

func TestEnableCmd_DryRun(t *testing.T) {
	resetEnableFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp/infra", 0755)
	os.WriteFile("workloads/testgroup/testapp/app.yaml",
		[]byte("apiVersion: argoproj.io/v1alpha1\nkind: Application\n"), 0644)
	os.WriteFile("workloads/testgroup/testapp/infra/gateway.yaml",
		[]byte("apiVersion: gateway.networking.k8s.io/v1\nkind: HTTPRoute\n"), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"enable", "testgroup/testapp", "--dry-run", "-y"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("enable dry-run failed: %v", err)
	}
}

func TestDisableCmd_InvalidFormat(t *testing.T) {
	resetDisableFlags()
	rootCmd.SetArgs([]string{"disable", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestDisableCmd_NotEnabled(t *testing.T) {
	resetDisableFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"disable", "testgroup/testapp"})
	err := rootCmd.Execute()
	restore()

	if err == nil || !strings.Contains(err.Error(), "not enabled") {
		t.Errorf("expected 'not enabled', got %v", err)
	}
}

func TestDeleteCmd_NoArg(t *testing.T) {
	resetDeleteFlags()
	rootCmd.SetArgs([]string{"delete"})
	err := rootCmd.Execute()
	if err == nil {
		t.Error("expected error for missing arg")
	}
}

func TestDeleteCmd_InvalidFormat(t *testing.T) {
	resetDeleteFlags()
	rootCmd.SetArgs([]string{"delete", "no-slash"})
	err := rootCmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("expected invalid format error, got %v", err)
	}
}

func TestDeleteCmd_WorkloadNotFound(t *testing.T) {
	resetDeleteFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"delete", "missing/workload"})
	err := rootCmd.Execute()
	restore()

	if err == nil || !strings.Contains(err.Error(), "workload not found") {
		t.Errorf("expected 'workload not found', got %v", err)
	}
}

func TestDeleteCmd_StillEnabled(t *testing.T) {
	resetDeleteFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)
	os.MkdirAll("gitops/workloads/testgroup", 0755)
	os.WriteFile("gitops/workloads/testgroup/testapp.yaml", []byte("enabled"), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"delete", "testgroup/testapp", "-y"})
	err := rootCmd.Execute()
	restore()

	if err == nil || !strings.Contains(err.Error(), "still enabled") {
		t.Errorf("expected 'still enabled', got %v", err)
	}
}

func TestDeleteCmd_DryRun(t *testing.T) {
	resetDeleteFlags()
	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"delete", "testgroup/testapp", "--dry-run", "-y"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("delete dry-run failed: %v", err)
	}
}
