package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func setupRepoRoot(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "Makefile"), []byte(".PHONY: all\nall:\n"), 0644); err != nil {
		t.Fatal(err)
	}
	templatesDir := filepath.Join(dir, "templates", "gold")
	if err := os.MkdirAll(templatesDir, 0755); err != nil {
		t.Fatal(err)
	}

	InitTemplateFS()
	return dir
}

func chdir(t *testing.T, dir string) func() {
	t.Helper()
	orig, _ := os.Getwd()
	os.Chdir(dir)
	return func() { os.Chdir(orig) }
}
