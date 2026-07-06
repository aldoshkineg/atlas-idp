package config

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

//go:embed config.yaml
var defaultConfigData []byte

type Config struct {
	Templates TemplatesConfig `yaml:"templates"`
	Scaffold  ScaffoldConfig  `yaml:"scaffold"`
	Gitops    GitopsConfig    `yaml:"gitops"`
	Defaults  DefaultsConfig  `yaml:"defaults"`
	Seed      SeedConfig      `yaml:"seed"`
	Backup    BackupConfig    `yaml:"backup"`
}

type TemplatesConfig struct {
	Dir string `yaml:"dir"`
}

type ScaffoldConfig struct {
	Dir string `yaml:"dir"`
}

type GitopsConfig struct {
	WorkloadsDir     string `yaml:"workloads_dir"`
	GatewayFile      string `yaml:"gateway_file"`
	GatewayRoutesDir string `yaml:"gateway_routes_dir"`
}

type DefaultsConfig struct {
	RepoPath        string `yaml:"repo_path"`
	GatewayPort     string `yaml:"gateway_port"`
	ChartRevision   string `yaml:"chart_revision"`
	TargetRevision  string `yaml:"target_revision"`
	HostnamePattern string `yaml:"hostname_pattern"`
}

type SeedConfig struct {
	Keys []SeedKey `yaml:"keys"`
}

type SeedKey struct {
	Name      string `yaml:"name"`
	Generator string `yaml:"generator"`
	Length    int    `yaml:"length"`
	EnvKey    string `yaml:"env_key"`
}

type BackupConfig struct {
	ClusterPattern string `yaml:"cluster_pattern"`
	Namespace      string `yaml:"namespace"`
}

func Load() (*Config, error) {
	var cfg Config
	if err := yaml.Unmarshal(defaultConfigData, &cfg); err != nil {
		return nil, fmt.Errorf("parse default config: %w", err)
	}

	cfg.applyDefaults()

	overlay, err := loadOverlay()
	if err == nil {
		cfg = merge(cfg, *overlay)
	}

	userCfg, err := loadUserConfig()
	if err == nil {
		cfg = merge(cfg, *userCfg)
	}

	cfg.resolvePaths()

	return &cfg, nil
}

func (c *Config) applyDefaults() {
	if c.Templates.Dir == "" {
		c.Templates.Dir = "templates/gold"
	}
	if c.Scaffold.Dir == "" {
		c.Scaffold.Dir = "workloads"
	}
	if c.Gitops.WorkloadsDir == "" {
		c.Gitops.WorkloadsDir = "gitops/workloads"
	}
	if c.Gitops.GatewayFile == "" {
		c.Gitops.GatewayFile = "gitops/platform/layers/networking/values/gateway-resources/gateway.yaml"
	}
	if c.Gitops.GatewayRoutesDir == "" {
		c.Gitops.GatewayRoutesDir = "gitops/platform/layers/networking/values/gateway-routes"
	}
	if c.Defaults.RepoPath == "" {
		c.Defaults.RepoPath = "."
	}
	if c.Defaults.GatewayPort == "" {
		c.Defaults.GatewayPort = "8080"
	}
	if c.Defaults.ChartRevision == "" {
		c.Defaults.ChartRevision = "main"
	}
	if c.Defaults.TargetRevision == "" {
		c.Defaults.TargetRevision = "main"
	}
	if c.Defaults.HostnamePattern == "" {
		c.Defaults.HostnamePattern = "{{APP}}.atlas"
	}
	if c.Backup.ClusterPattern == "" {
		c.Backup.ClusterPattern = "{{APP}}-db"
	}
	if c.Backup.Namespace == "" {
		c.Backup.Namespace = "database"
	}
}

func (c *Config) resolvePaths() {
	var relativePaths []*string
	for _, p := range []*string{&c.Templates.Dir, &c.Scaffold.Dir, &c.Gitops.WorkloadsDir, &c.Gitops.GatewayFile, &c.Gitops.GatewayRoutesDir} {
		if *p != "" && !filepath.IsAbs(*p) {
			relativePaths = append(relativePaths, p)
		}
	}
	if len(relativePaths) == 0 {
		return
	}

	repoRoot, err := FindRepoRoot()
	if err != nil {
		return
	}

	for _, p := range relativePaths {
		*p = filepath.Join(repoRoot, *p)
	}
}

func FindRepoRoot() (string, error) {
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

func UserConfigDir() string {
	home, _ := os.UserHomeDir()
	if home == "" {
		return ""
	}
	return filepath.Join(home, ".config", "atlasctl")
}

func UserConfigPath() string {
	return filepath.Join(UserConfigDir(), "config.yaml")
}

func loadOverlay() (*Config, error) {
	name, _ := os.Executable()
	cfgPath := filepath.Join(filepath.Dir(name), "atlasctl.yaml")
	if _, err := os.Stat(cfgPath); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(cfgPath)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse overlay config: %w", err)
	}
	return &cfg, nil
}

func loadUserConfig() (*Config, error) {
	if _, disabled := os.LookupEnv("ATLASCTL_NO_USER_CONFIG"); disabled {
		return nil, fmt.Errorf("disabled by ATLASCTL_NO_USER_CONFIG")
	}
	cfgPath := UserConfigPath()
	if _, err := os.Stat(cfgPath); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(cfgPath)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse user config: %w", err)
	}
	return &cfg, nil
}

func merge(base, over Config) Config {
	if over.Templates.Dir != "" {
		base.Templates.Dir = over.Templates.Dir
	}
	if over.Scaffold.Dir != "" {
		base.Scaffold.Dir = over.Scaffold.Dir
	}
	if over.Gitops.WorkloadsDir != "" {
		base.Gitops.WorkloadsDir = over.Gitops.WorkloadsDir
	}
	if over.Gitops.GatewayFile != "" {
		base.Gitops.GatewayFile = over.Gitops.GatewayFile
	}
	if over.Gitops.GatewayRoutesDir != "" {
		base.Gitops.GatewayRoutesDir = over.Gitops.GatewayRoutesDir
	}
	if over.Defaults.RepoPath != "" {
		base.Defaults.RepoPath = over.Defaults.RepoPath
	}
	if over.Defaults.GatewayPort != "" {
		base.Defaults.GatewayPort = over.Defaults.GatewayPort
	}
	if over.Defaults.ChartRevision != "" {
		base.Defaults.ChartRevision = over.Defaults.ChartRevision
	}
	if over.Defaults.TargetRevision != "" {
		base.Defaults.TargetRevision = over.Defaults.TargetRevision
	}
	if over.Defaults.HostnamePattern != "" {
		base.Defaults.HostnamePattern = over.Defaults.HostnamePattern
	}
	if len(over.Seed.Keys) > 0 {
		base.Seed.Keys = over.Seed.Keys
	}
	if over.Backup.ClusterPattern != "" {
		base.Backup.ClusterPattern = over.Backup.ClusterPattern
	}
	if over.Backup.Namespace != "" {
		base.Backup.Namespace = over.Backup.Namespace
	}
	return base
}
