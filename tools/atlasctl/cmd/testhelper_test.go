package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// setupRepoRoot creates a temp dir with Makefile so InitCfg/InitTemplatesFS
// resolve paths under the temp dir. Templates are empty — suitable for
// commands that don't render templates (enable, disable, status, list, etc.).
func setupRepoRoot(t *testing.T) string {
	t.Helper()
	t.Setenv("ATLASCTL_NO_USER_CONFIG", "1")
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte(".PHONY: all\nall:\n"), 0644); err != nil {
		t.Fatal(err)
	}
	templatesDir := filepath.Join(dir, "templates", "gold")
	if err := os.MkdirAll(templatesDir, 0755); err != nil {
		t.Fatal(err)
	}

	orig, _ := os.Getwd()
	os.Chdir(dir)
	TemplatesFS = nil
	Cfg = nil
	if err := InitTemplatesFS(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chdir(orig) })
	return dir
}

// setupRepoWithTemplates creates a temp dir with Makefile and symlinks
// the real templates/ directory. Use for tests that render templates (new, seed).
func setupRepoWithTemplates(t *testing.T) string {
	t.Helper()
	t.Setenv("ATLASCTL_NO_USER_CONFIG", "1")
	orig, _ := os.Getwd()

	// Find the real templates directory
	repoRoot := orig
	for {
		if _, err := os.Stat(filepath.Join(repoRoot, "templates", "gold")); err == nil {
			break
		}
		parent := filepath.Dir(repoRoot)
		if parent == repoRoot {
			t.Skip("templates/gold not found in repo hierarchy")
		}
		repoRoot = parent
	}

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte(".PHONY: all\nall:\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(repoRoot, "templates"), filepath.Join(dir, "templates")); err != nil {
		t.Fatal(err)
	}

	os.Chdir(dir)
	TemplatesFS = nil
	Cfg = nil
	if err := InitTemplatesFS(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chdir(orig) })
	return dir
}

func chdir(t *testing.T, dir string) func() {
	t.Helper()
	orig, _ := os.Getwd()
	os.Chdir(dir)
	return func() { os.Chdir(orig) }
}
