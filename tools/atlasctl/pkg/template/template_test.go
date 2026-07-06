package template

import (
	"testing"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

func testDefaults() *config.DefaultsConfig {
	return &config.DefaultsConfig{
		RepoPath:        ".",
		GatewayPort:     "8080",
		ChartRevision:   "main",
		TargetRevision:  "main",
		HostnamePattern: "{{APP}}.atlas",
	}
}

func TestRender(t *testing.T) {
	dcfg := testDefaults()
	tests := []struct {
		name     string
		input    string
		vars     Vars
		expected string
	}{
		{
			name:  "simple app replacement",
			input: "name: {{APP}}",
			vars:  Vars{APP: "myapp"},
			expected: "name: myapp",
		},
		{
			name:  "all base vars",
			input: "{{APP}} {{APP_UC}} {{GROUP}} {{GROUP_UC}} {{NAMESPACE}}",
			vars: Vars{
				APP:       "my-app",
				APP_UC:    "MY_APP",
				GROUP:     "team-a",
				GROUP_UC:  "TEAM_A",
				NAMESPACE: "team-a-my-app",
			},
			expected: "my-app MY_APP team-a TEAM_A team-a-my-app",
		},
		{
			name:  "gateway port default",
			input: "port: {{GATEWAY_PORT}}",
			vars:  Vars{APP: "x"},
			expected: "port: 8080",
		},
		{
			name:  "hostname default",
			input: "host: {{HOSTNAME}}",
			vars:  Vars{APP: "myapp"},
			expected: "host: myapp.atlas",
		},
		{
			name:  "chart repo defaults to repo url",
			input: "{{CHART_REPO}}",
			vars:  Vars{APP: "x", REPO_URL: "https://github.com/org/repo.git"},
			expected: "https://github.com/org/repo.git",
		},
		{
			name:  "helm settings empty when not helm",
			input: "{{REPO_HELM_SETTINGS}}{{GITOPS_HELM_SETTINGS}}",
			vars:  Vars{APP: "x"},
			expected: "",
		},
		{
			name:  "all empty vars produce defaults",
			input: "{{APP}}{{APP_UC}}{{GROUP}}{{GROUP_UC}}{{NAMESPACE}}{{REPO_URL}}{{REPO_PATH}}{{HOSTNAME}}{{GATEWAY_PORT}}{{CHART_REPO}}{{CHART_REVISION}}{{CHART_PATH}}{{TARGET_REVISION}}{{SERVICE_ACCOUNTS}}",
			vars:  Vars{},
			expected: "..atlas8080mainmain",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Render(tt.input, tt.vars, dcfg)
			if got != tt.expected {
				t.Errorf("Render() = %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestDefaults(t *testing.T) {
	dcfg := testDefaults()
	v := Defaults(Vars{APP: "myapp"}, dcfg)
	if v.REPO_PATH != "." {
		t.Errorf("REPO_PATH default should be '.' got %q", v.REPO_PATH)
	}
	if v.GATEWAY_PORT != "8080" {
		t.Errorf("GATEWAY_PORT default should be 8080 got %q", v.GATEWAY_PORT)
	}
	if v.HOSTNAME != "myapp.atlas" {
		t.Errorf("HOSTNAME default should be 'myapp.atlas' got %q", v.HOSTNAME)
	}
	if v.TARGET_REVISION != "main" {
		t.Errorf("TARGET_REVISION default should be 'main' got %q", v.TARGET_REVISION)
	}
	if v.CHART_REVISION != "main" {
		t.Errorf("CHART_REVISION default should be 'main' got %q", v.CHART_REVISION)
	}
}

func TestDefaults_ChartRepoFallsBackToRepoURL(t *testing.T) {
	dcfg := testDefaults()
	v := Defaults(Vars{APP: "x", REPO_URL: "https://example.com/repo.git"}, dcfg)
	if v.CHART_REPO != "https://example.com/repo.git" {
		t.Errorf("CHART_REPO should default to REPO_URL, got %q", v.CHART_REPO)
	}
}

func TestRender_GatewayYaml(t *testing.T) {
	dcfg := testDefaults()
	v := Vars{
		APP:          "seal",
		NAMESPACE:    "aldoshkineg-seal",
		HOSTNAME:     "seal.atlas",
		GATEWAY_PORT: "8080",
	}
	input := `apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{APP}}-route
  namespace: {{NAMESPACE}}
spec:
  parentRefs:
    - name: platform-gateway
      namespace: kube-system
      sectionName: https-{{APP}}
  hostnames:
    - {{HOSTNAME}}
  rules:
    - backendRefs:
        - name: {{APP}}
          port: {{GATEWAY_PORT}}`

	expected := `apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: seal-route
  namespace: aldoshkineg-seal
spec:
  parentRefs:
    - name: platform-gateway
      namespace: kube-system
      sectionName: https-seal
  hostnames:
    - seal.atlas
  rules:
    - backendRefs:
        - name: seal
          port: 8080`

	got := Render(input, v, dcfg)
	if got != expected {
		t.Errorf("Render() = %q, want %q", got, expected)
	}
}

func TestRender_AllVarsReplaced(t *testing.T) {
	dcfg := testDefaults()
	v := Vars{
		APP:       "myapp",
		APP_UC:    "MYAPP",
		GROUP:     "team",
		GROUP_UC:  "TEAM",
		NAMESPACE: "team-myapp",
		REPO_URL:  "https://github.com/team/myapp.git",
		REPO_PATH: "charts/myapp",
		HOSTNAME:  "myapp.atlas",
	}

	input := "{{APP}} {{APP_UC}} {{GROUP}} {{GROUP_UC}} {{NAMESPACE}} {{REPO_URL}} {{REPO_PATH}} {{HOSTNAME}}"
	expected := "myapp MYAPP team TEAM team-myapp https://github.com/team/myapp.git charts/myapp myapp.atlas"

	got := Render(input, v, dcfg)
	if got != expected {
		t.Errorf("Render() = %q, want %q", got, expected)
	}
}

func TestRender_UnknownVarsPreserved(t *testing.T) {
	dcfg := testDefaults()
	input := "{{APP}} {{UNKNOWN_VAR}}"
	v := Vars{APP: "myapp"}

	got := Render(input, v, dcfg)
	expected := "myapp {{UNKNOWN_VAR}}"
	if got != expected {
		t.Errorf("unknown vars should be preserved, got %q, want %q", got, expected)
	}
}

func TestRender_HelmSettings(t *testing.T) {
	dcfg := testDefaults()
	v := Vars{
		APP:                "myapp",
		HelmValuesIndented: "        replicaCount: 3",
		GitopsHelmValues:   "          replicaCount: 3",
	}

	input := `{{REPO_HELM_SETTINGS}}
{{GITOPS_HELM_SETTINGS}}`
	expected := `        replicaCount: 3
          replicaCount: 3`

	got := Render(input, v, dcfg)
	if got != expected {
		t.Errorf("Render() = %q, want %q", got, expected)
	}
}
