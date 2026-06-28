package template

import (
	"fmt"
	"io/fs"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

type Vars struct {
	APP          string
	APP_UC       string
	GROUP        string
	GROUP_UC     string
	NAMESPACE    string
	REPO_URL     string
	REPO_PATH    string
	HOSTNAME     string
	GATEWAY_PORT string

	CHART_REPO      string
	CHART_REVISION  string
	CHART_PATH      string
	TARGET_REVISION string

	SERVICE_ACCOUNTS string

	HelmValuesIndented string
	GitopsHelmValues   string
}

func Defaults(v Vars, cfg *config.DefaultsConfig) Vars {
	if v.REPO_PATH == "" {
		v.REPO_PATH = cfg.RepoPath
	}
	if v.GATEWAY_PORT == "" {
		v.GATEWAY_PORT = cfg.GatewayPort
	}
	if v.CHART_REPO == "" {
		v.CHART_REPO = v.REPO_URL
	}
	if v.CHART_REVISION == "" {
		v.CHART_REVISION = cfg.ChartRevision
	}
	if v.TARGET_REVISION == "" {
		v.TARGET_REVISION = cfg.TargetRevision
	}
	if v.HOSTNAME == "" {
		v.HOSTNAME = strings.ReplaceAll(cfg.HostnamePattern, "{{APP}}", v.APP)
	}
	return v
}

func Render(content string, v Vars, cfg *config.DefaultsConfig) string {
	v = Defaults(v, cfg)

	replacements := map[string]string{
		"{{APP}}":                v.APP,
		"{{APP_UC}}":             v.APP_UC,
		"{{GROUP}}":              v.GROUP,
		"{{GROUP_UC}}":           v.GROUP_UC,
		"{{NAMESPACE}}":          v.NAMESPACE,
		"{{REPO_URL}}":           v.REPO_URL,
		"{{REPO_PATH}}":          v.REPO_PATH,
		"{{HOSTNAME}}":           v.HOSTNAME,
		"{{GATEWAY_PORT}}":       v.GATEWAY_PORT,
		"{{CHART_REPO}}":         v.CHART_REPO,
		"{{CHART_REVISION}}":     v.CHART_REVISION,
		"{{CHART_PATH}}":         v.CHART_PATH,
		"{{TARGET_REVISION}}":    v.TARGET_REVISION,
		"{{SERVICE_ACCOUNTS}}":   v.SERVICE_ACCOUNTS,
		"{{REPO_HELM_SETTINGS}}": v.HelmValuesIndented,
		"{{GITOPS_HELM_SETTINGS}}": v.GitopsHelmValues,
	}

	for k, val := range replacements {
		content = strings.ReplaceAll(content, k, val)
	}
	return content
}

func RenderFile(templates fs.FS, path string, v Vars, cfg *config.DefaultsConfig) (string, error) {
	data, err := fs.ReadFile(templates, path)
	if err != nil {
		return "", fmt.Errorf("read template %s: %w", path, err)
	}
	return Render(string(data), v, cfg), nil
}
