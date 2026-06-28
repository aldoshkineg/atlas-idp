package template

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

func findRepoRoot() string {
	dir, _ := os.Getwd()
	for {
		if _, err := os.Stat(filepath.Join(dir, "Makefile")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func TestGoldenFileRender(t *testing.T) {
	repoRoot := findRepoRoot()
	if repoRoot == "" {
		t.Skip("repo root not found")
	}

	templatesDir := filepath.Join(repoRoot, "templates", "gold")

	files := []string{
		"app.yaml.tmpl",
		"secrets.yaml.tmpl",
		"README.md.tmpl",
		"vault/policy.hcl.tmpl",
		"vault/k8s-auth-role.yaml.tmpl",
		"vault/seed-mapping.conf.tmpl",
		"monitoring/pod-monitor.yaml.tmpl",
		"monitoring/prometheus-rule.yaml.tmpl",
		"infra/gateway.yaml.tmpl",
		"infra/network-policy.yaml.tmpl",
		"infra/resource-quota.yaml.tmpl",
		"infra/limit-range.yaml.tmpl",
		"infra/keda-scaledobject.yaml.tmpl",
		"infra/ccnp-ingress.yaml.tmpl",
	}

	cfg := &config.DefaultsConfig{
		RepoPath:        ".",
		GatewayPort:     "8080",
		ChartRevision:   "main",
		TargetRevision:  "main",
		HostnamePattern: "{{APP}}.atlas",
	}

	v := Vars{
		APP:              "testapp",
		APP_UC:           "TESTAPP",
		GROUP:            "testgroup",
		GROUP_UC:         "TESTGROUP",
		NAMESPACE:        "testgroup-testapp",
		REPO_URL:         "https://github.com/testgroup/testapp.git",
		REPO_PATH:        ".",
		HOSTNAME:         "testapp.atlas",
		GATEWAY_PORT:     "8080",
		SERVICE_ACCOUNTS: "testapp",
	}

	for _, f := range files {
		t.Run(f, func(t *testing.T) {
			src := filepath.Join(templatesDir, f)
			data, err := os.ReadFile(src)
			if err != nil {
				t.Fatalf("read %s: %v", src, err)
			}

			result := Render(string(data), v, cfg)

			if strings.Contains(result, "{{") && strings.Contains(result, "}}") {
				t.Errorf("template %s still contains unreplaced {{...}} placeholders", f)
			}

			if len(result) == 0 {
				t.Errorf("template %s rendered to empty string", f)
			}
		})
	}
}
