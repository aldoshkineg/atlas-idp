//go:build integration

package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSmokeNewSeedEnableStatusDisableDelete(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration smoke test in short mode")
	}

	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	tmpDir := t.TempDir()
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	repoRoot := filepath.Dir(filepath.Dir(origDir))
	if _, err := os.Stat(filepath.Join(repoRoot, "templates", "gold")); os.IsNotExist(err) {
		t.Skip("templates/gold not found — not in repo root")
	}

	os.Symlink(filepath.Join(repoRoot, "templates"), filepath.Join(tmpDir, "templates"))
	os.WriteFile(filepath.Join(tmpDir, "Makefile"), []byte(".PHONY: all\nall:\n"), 0644)

	InitTemplateFS()

	// new
	resetNewFlags()
	restore := suppressOutput()
	rootCmd.SetArgs([]string{"new", "smoketest", "--group", "smoke", "--repo", "https://github.com/test/smoke.git", "-y"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("new command failed: %v", err)
	}

	workloadDir := filepath.Join(tmpDir, "workloads", "smoke", "smoketest")
	if _, err := os.Stat(workloadDir); os.IsNotExist(err) {
		t.Fatal("workload dir not created by new")
	}

	if _, err := os.Stat(filepath.Join(workloadDir, "app.yaml")); os.IsNotExist(err) {
		t.Fatal("app.yaml not created by new")
	}

	// seed (dry-run)
	resetSeedFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"seed", "smoke/smoketest", "--dry-run", "-y"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("seed dry-run failed: %v", err)
	}

	// enable (dry-run)
	resetEnableFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"enable", "smoke/smoketest", "--dry-run", "-y"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("enable dry-run failed: %v", err)
	}

	// status
	resetStatusFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"status", "smoke/smoketest"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("status failed: %v", err)
	}

	// status --json
	resetStatusFlags()
	capture := captureOutput()
	rootCmd.SetArgs([]string{"status", "smoke/smoketest", "--json"})
	err = rootCmd.Execute()
	out := capture()
	if err != nil {
		t.Fatalf("status --json failed: %v", err)
	}
	if !strings.Contains(out, `"name": "smoke/smoketest"`) {
		t.Errorf("status --json missing workload name, got: %s", out)
	}

	// list
	resetListFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"list"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("list failed: %v", err)
	}

	// list --json
	resetListFlags()
	capture = captureOutput()
	rootCmd.SetArgs([]string{"list", "--json"})
	err = rootCmd.Execute()
	out = capture()
	if err != nil {
		t.Fatalf("list --json failed: %v", err)
	}
	if !strings.Contains(out, `"name": "smoke/smoketest"`) {
		t.Errorf("list --json missing workload, got: %s", out)
	}

	// backup (dry-run)
	resetBackupFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"backup", "smoke/smoketest", "--dry-run"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("backup dry-run failed: %v", err)
	}

	// disable (dry-run) — needs gitops file to exist to get past "not enabled" check
	os.MkdirAll(filepath.Join(tmpDir, "gitops", "workloads", "smoke"), 0755)
	os.WriteFile(filepath.Join(tmpDir, "gitops", "workloads", "smoke", "smoketest.yaml"), []byte("x"), 0644)
	resetDisableFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"disable", "smoke/smoketest", "--dry-run", "-y"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("disable dry-run failed: %v", err)
	}

	// delete (dry-run) — but it's "enabled", so should fail
	resetDeleteFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"delete", "smoke/smoketest", "--dry-run", "-y"})
	err = rootCmd.Execute()
	restore()
	if err == nil {
		t.Fatal("expected 'still enabled' error from delete")
	}
	if !strings.Contains(err.Error(), "still enabled") {
		t.Errorf("expected 'still enabled', got: %v", err)
	}

	// delete after removing gitops file
	os.Remove(filepath.Join(tmpDir, "gitops", "workloads", "smoke", "smoketest.yaml"))
	resetDeleteFlags()
	restore = suppressOutput()
	rootCmd.SetArgs([]string{"delete", "smoke/smoketest", "-y"})
	err = rootCmd.Execute()
	restore()
	if err != nil {
		t.Fatalf("delete failed: %v", err)
	}
	if _, err := os.Stat(workloadDir); !os.IsNotExist(err) {
		t.Fatal("workload dir was not removed by delete")
	}
}

func captureOutput() func() string {
	r, w, _ := os.Pipe()
	orig := os.Stdout
	os.Stdout = w
	done := make(chan string, 1)
	go func() {
		var buf strings.Builder
		readBuf := make([]byte, 4096)
		for {
			n, err := r.Read(readBuf)
			if n > 0 {
				buf.Write(readBuf[:n])
			}
			if err != nil {
				break
			}
		}
		done <- buf.String()
	}()
	return func() string {
		w.Close()
		os.Stdout = orig
		return <-done
	}
}
