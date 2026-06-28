package config

import (
	"os"
	"testing"
)

func TestLoadDefaults(t *testing.T) {
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.Templates.Path != "templates" {
		t.Errorf("expected templates.path 'templates', got %q", cfg.Templates.Path)
	}
	if cfg.Templates.GoldDir != "gold" {
		t.Errorf("expected templates.gold_dir 'gold', got %q", cfg.Templates.GoldDir)
	}
	if cfg.Scaffold.Directory != "workloads" {
		t.Errorf("expected scaffold.directory 'workloads', got %q", cfg.Scaffold.Directory)
	}
	if cfg.Gitops.WorkloadsDir != "gitops/workloads" {
		t.Errorf("expected gitops.workloads_dir 'gitops/workloads', got %q", cfg.Gitops.WorkloadsDir)
	}
	if cfg.Gitops.GatewayFile == "" {
		t.Errorf("gateway_file should not be empty")
	}
	if cfg.Gitops.GatewayRoutesDir == "" {
		t.Errorf("gateway_routes_dir should not be empty")
	}
	if cfg.Defaults.RepoPath != "." {
		t.Errorf("expected repo_path '.', got %q", cfg.Defaults.RepoPath)
	}
	if cfg.Defaults.GatewayPort != "8080" {
		t.Errorf("expected gateway_port '8080', got %q", cfg.Defaults.GatewayPort)
	}
	if cfg.Defaults.ChartRevision != "main" {
		t.Errorf("expected chart_revision 'main', got %q", cfg.Defaults.ChartRevision)
	}
	if cfg.Defaults.TargetRevision != "main" {
		t.Errorf("expected target_revision 'main', got %q", cfg.Defaults.TargetRevision)
	}
	if cfg.Defaults.HostnamePattern != "{{APP}}.atlas" {
		t.Errorf("expected hostname_pattern '{{APP}}.atlas', got %q", cfg.Defaults.HostnamePattern)
	}
	if len(cfg.Seed.Keys) != 4 {
		t.Errorf("expected 4 seed keys, got %d", len(cfg.Seed.Keys))
	}
}

func TestApplyDefaults_EmptyConfig(t *testing.T) {
	cfg := &Config{}
	cfg.applyDefaults()

	if cfg.Templates.Path != "templates" {
		t.Errorf("expected templates.path 'templates'")
	}
	if cfg.Templates.GoldDir != "gold" {
		t.Errorf("expected templates.gold_dir 'gold'")
	}
	if cfg.Scaffold.Directory != "workloads" {
		t.Errorf("expected scaffold.directory 'workloads'")
	}
	if cfg.Gitops.WorkloadsDir != "gitops/workloads" {
		t.Errorf("expected gitops.workloads_dir 'gitops/workloads'")
	}
	if cfg.Gitops.GatewayFile == "" {
		t.Errorf("gateway_file should have default")
	}
}

func TestMerge(t *testing.T) {
	base := Config{
		Templates: TemplatesConfig{Path: "custom-templates", GoldDir: "gold"},
		Scaffold:  ScaffoldConfig{Directory: "workloads"},
		Gitops: GitopsConfig{
			WorkloadsDir:     "gitops/workloads",
			GatewayFile:      "gw.yaml",
			GatewayRoutesDir: "routes",
		},
		Defaults: DefaultsConfig{
			RepoPath:    ".",
			GatewayPort: "8080",
		},
	}

	over := Config{
		Defaults: DefaultsConfig{
			GatewayPort: "9090",
		},
	}

	result := merge(base, over)
	if result.Templates.Path != "custom-templates" {
		t.Errorf("Templates.Path should stay custom, got %q", result.Templates.Path)
	}
	if result.Defaults.GatewayPort != "9090" {
		t.Errorf("GatewayPort should be overridden to '9090', got %q", result.Defaults.GatewayPort)
	}
}

func TestMergeOverrides(t *testing.T) {
	base := Config{}
	base.applyDefaults()

	over := Config{
		Templates: TemplatesConfig{Path: "other-templates"},
		Gitops:    GitopsConfig{WorkloadsDir: "other/workloads"},
	}

	result := merge(base, over)
	if result.Templates.Path != "other-templates" {
		t.Errorf("Templates.Path should be overridden")
	}
	if result.Gitops.WorkloadsDir != "other/workloads" {
		t.Errorf("Gitops.WorkloadsDir should be overridden")
	}
}

func TestOverlayFromBinaryDir(t *testing.T) {
	if _, err := os.Stat("atlasctl.yaml"); os.IsNotExist(err) {
		t.Log("no overlay config file, skipping")
		return
	}
	cfg, err := loadOverlay()
	if err != nil {
		t.Fatalf("loadOverlay() error = %v", err)
	}
	if cfg == nil {
		t.Fatal("expected non-nil config")
	}
}

func TestSeedKeys(t *testing.T) {
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range cfg.Seed.Keys {
		if k.Name == "" {
			t.Error("seed key missing Name")
		}
		if k.Generator != "base64" && k.Generator != "hex" {
			t.Errorf("seed key %q has unsupported generator %q", k.Name, k.Generator)
		}
		if k.Length <= 0 {
			t.Errorf("seed key %q has invalid length %d", k.Name, k.Length)
		}
		if k.EnvKey == "" {
			t.Errorf("seed key %q missing EnvKey", k.Name)
		}
	}
}
