package cmd

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

var (
	TemplatesFS fs.FS
	Cfg         *config.Config
)

func InitTemplateFS() {
	cfg, err := config.Load()
	if err != nil {
		panic(err)
	}
	Cfg = cfg

	fs, err := findTemplatesFS(cfg.Templates.Path)
	if err != nil {
		panic(err)
	}
	TemplatesFS = fs
}

func findTemplatesFS(templatesPath string) (fs.FS, error) {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return nil, fmt.Errorf("cannot find repo root: %w", err)
	}
	templatesDir := filepath.Join(repoRoot, templatesPath)
	if _, err := os.Stat(templatesDir); err != nil {
		return nil, fmt.Errorf("templates dir %s: %w", templatesDir, err)
	}
	return os.DirFS(templatesDir), nil
}

func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "Makefile")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("repo root not found (no Makefile in parent dirs)")
		}
		dir = parent
	}
}
