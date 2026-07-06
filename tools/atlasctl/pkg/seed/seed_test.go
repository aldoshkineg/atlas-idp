package seed

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

func writeSeedFile(t *testing.T, dir, prefix, content string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".secret-seed"), []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestLoadParams(t *testing.T) {
	cfg := loadTestConfig(t)

	tests := []struct {
		name    string
		content string
		wantErr bool
		check   func(*testing.T, *Params)
	}{
		{
			name: "valid seed file",
			content: `# testg/testapp - atlasctl seed environment file
VL_TESTG_TESTAPP_DB_PASSWORD=dbpass123
VL_TESTG_TESTAPP_S3_ACCESS_KEY=s3access
VL_TESTG_TESTAPP_S3_SECRET_KEY=s3secret
VL_TESTG_TESTAPP_REDIS_PASSWORD=redispass`,
			wantErr: false,
			check: func(t *testing.T, p *Params) {
				if p.DBPassword != "dbpass123" {
					t.Errorf("DBPassword = %q, want %q", p.DBPassword, "dbpass123")
				}
				if p.S3AccessKey != "s3access" {
					t.Errorf("S3AccessKey = %q", p.S3AccessKey)
				}
				if p.S3SecretKey != "s3secret" {
					t.Errorf("S3SecretKey = %q", p.S3SecretKey)
				}
				if p.RedisPass != "redispass" {
					t.Errorf("RedisPass = %q", p.RedisPass)
				}
			},
		},
		{
			name: "with extra secrets",
			content: `# test
VL_TESTG_TESTAPP_DB_PASSWORD=p1
VL_TESTG_TESTAPP_S3_ACCESS_KEY=k1
VL_TESTG_TESTAPP_S3_SECRET_KEY=k2
VL_TESTG_TESTAPP_REDIS_PASSWORD=p2
VL_TESTG_TESTAPP_PDF_CERT_B64=certdata
VL_TESTG_TESTAPP_PDF_KEY_B64=keydata`,
			wantErr: false,
			check: func(t *testing.T, p *Params) {
				if p.ExtraSecrets["PDF_CERT_B64"] != "certdata" {
					t.Errorf("ExtraSecrets PDF_CERT_B64 = %q", p.ExtraSecrets["PDF_CERT_B64"])
				}
				if p.ExtraSecrets["PDF_KEY_B64"] != "keydata" {
					t.Errorf("ExtraSecrets PDF_KEY_B64 = %q", p.ExtraSecrets["PDF_KEY_B64"])
				}
			},
		},
		{
			name:    "missing .secret-seed",
			content: "",
			wantErr: true,
		},
		{
			name: "empty values",
			content: `VL_X_Y_DB_PASSWORD=
VL_X_Y_S3_ACCESS_KEY=key1
VL_X_Y_S3_SECRET_KEY=key2
VL_X_Y_REDIS_PASSWORD=key3`,
			wantErr: false,
			check: func(t *testing.T, p *Params) {
				if p.DBPassword != "" {
					t.Errorf("DBPassword should be empty")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			if tt.content != "" {
				writeSeedFile(t, dir, "", tt.content)
			}

			svc := New(nil, nil, cfg)
			params, err := svc.LoadParams(Workload{
				Group: "testg",
				App:   "testapp",
				Dir:   dir,
			})

			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got none")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil {
				tt.check(t, params)
			}
		})
	}
}

func TestValidateParams(t *testing.T) {
	cfg := loadTestConfig(t)
	svc := New(nil, nil, cfg)

	tests := []struct {
		name    string
		params  *Params
		wantErr bool
	}{
		{
			name: "all fields present",
			params: &Params{
				DBPassword:  "p1",
				S3AccessKey: "k1",
				S3SecretKey: "k2",
				RedisPass:   "p2",
			},
			wantErr: false,
		},
		{
			name: "missing DB_PASSWORD",
			params: &Params{
				DBPassword:  "",
				S3AccessKey: "k1",
				S3SecretKey: "k2",
				RedisPass:   "p2",
			},
			wantErr: true,
		},
		{
			name: "missing S3_ACCESS_KEY",
			params: &Params{
				DBPassword:  "p1",
				S3AccessKey: "",
				S3SecretKey: "k2",
				RedisPass:   "p2",
			},
			wantErr: true,
		},
		{
			name: "missing all",
			params: &Params{},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := svc.ValidateParams(tt.params)
			if tt.wantErr && err == nil {
				t.Fatal("expected error, got none")
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func loadTestConfig(t *testing.T) *config.Config {
	t.Helper()
	return &config.Config{
		Templates: config.TemplatesConfig{Dir: "templates/gold"},
		Scaffold:  config.ScaffoldConfig{Dir: "workloads"},
		Gitops: config.GitopsConfig{
			WorkloadsDir:     "gitops/workloads",
			GatewayFile:      "gitops/platform/layers/networking/values/gateway-resources/gateway.yaml",
			GatewayRoutesDir: "gitops/platform/layers/networking/values/gateway-routes",
		},
		Defaults: config.DefaultsConfig{
			RepoPath: ".", GatewayPort: "8080",
			ChartRevision: "main", TargetRevision: "main",
			HostnamePattern: "{{APP}}.atlas",
		},
		Seed: config.SeedConfig{
			Keys: []config.SeedKey{
				{Name: "DB_PASSWORD", Generator: "base64", Length: 24, EnvKey: "DB_PASSWORD"},
				{Name: "S3_ACCESS_KEY", Generator: "hex", Length: 16, EnvKey: "S3_ACCESS_KEY"},
				{Name: "S3_SECRET_KEY", Generator: "base64", Length: 32, EnvKey: "S3_SECRET_KEY"},
				{Name: "REDIS_PASSWORD", Generator: "base64", Length: 24, EnvKey: "REDIS_PASSWORD"},
			},
		},
	}
}
