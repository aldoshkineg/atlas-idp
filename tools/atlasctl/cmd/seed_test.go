package cmd

import (
	"os"
	"strings"
	"testing"
)

func resetSeedFlags() {
	seedCmdFlags = seedFlags{}
}

func TestSeedCmd_NoArg(t *testing.T) {
	resetNewFlags()
	resetSeedFlags()
	rootCmd.SetArgs([]string{"seed"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for missing arg")
	}
}

func TestSeedCmd_InvalidFormat(t *testing.T) {
	resetNewFlags()
	resetSeedFlags()
	rootCmd.SetArgs([]string{"seed", "no-slash"})
	err := rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for invalid format")
	}
	if !strings.Contains(err.Error(), "invalid format") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestSeedCmd_DryRun(t *testing.T) {
	resetNewFlags()
	resetSeedFlags()

	dir := setupRepoRoot(t)
	defer chdir(t, dir)()

	os.MkdirAll("workloads/testgroup/testapp", 0755)
	seedContent := `# TESTGROUP_TESTAPP - atlasctl seed
VL_TESTGROUP_TESTAPP_DB_PASSWORD=dbpass123
VL_TESTGROUP_TESTAPP_S3_ACCESS_KEY=s3access
VL_TESTGROUP_TESTAPP_S3_SECRET_KEY=s3secret
VL_TESTGROUP_TESTAPP_REDIS_PASSWORD=redispass`
	os.WriteFile("workloads/testgroup/testapp/.secret-seed", []byte(seedContent), 0644)

	restore := suppressOutput()
	rootCmd.SetArgs([]string{"seed", "testgroup/testapp", "--dry-run", "-y"})
	err := rootCmd.Execute()
	restore()

	if err != nil {
		t.Fatalf("seed dry-run failed: %v", err)
	}
}
