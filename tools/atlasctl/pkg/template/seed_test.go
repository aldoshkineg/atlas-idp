package template

import (
	"strings"
	"testing"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

func testSeedKeys() []config.SeedKey {
	return []config.SeedKey{
		{Name: "DB_PASSWORD", Generator: "base64", Length: 24, EnvKey: "DB_PASSWORD"},
		{Name: "S3_ACCESS_KEY", Generator: "hex", Length: 16, EnvKey: "S3_ACCESS_KEY"},
		{Name: "S3_SECRET_KEY", Generator: "base64", Length: 32, EnvKey: "S3_SECRET_KEY"},
		{Name: "REDIS_PASSWORD", Generator: "base64", Length: 24, EnvKey: "REDIS_PASSWORD"},
	}
}

func TestGenerateSeed(t *testing.T) {
	secrets, err := GenerateSeed(testSeedKeys())
	if err != nil {
		t.Fatalf("GenerateSeed() error = %v", err)
	}

	if len(secrets) != 4 {
		t.Errorf("expected 4 secrets, got %d", len(secrets))
	}

	for _, k := range []string{"DB_PASSWORD", "S3_ACCESS_KEY", "S3_SECRET_KEY", "REDIS_PASSWORD"} {
		if secrets[k] == "" {
			t.Errorf("%s should not be empty", k)
		}
	}

	if len(secrets["DB_PASSWORD"]) < 20 {
		t.Errorf("DB_PASSWORD too short: %d chars", len(secrets["DB_PASSWORD"]))
	}
	if len(secrets["S3_ACCESS_KEY"]) < 20 {
		t.Errorf("S3_ACCESS_KEY too short: %d chars", len(secrets["S3_ACCESS_KEY"]))
	}
	if len(secrets["S3_SECRET_KEY"]) < 30 {
		t.Errorf("S3_SECRET_KEY too short: %d chars", len(secrets["S3_SECRET_KEY"]))
	}
}

func TestGenerateSeed_Uniqueness(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 10; i++ {
		secrets, err := GenerateSeed(testSeedKeys())
		if err != nil {
			t.Fatal(err)
		}
		if seen[secrets["DB_PASSWORD"]] {
			t.Error("DB_PASSWORD should be unique")
		}
		if seen[secrets["S3_ACCESS_KEY"]] {
			t.Error("S3_ACCESS_KEY should be unique")
		}
		seen[secrets["DB_PASSWORD"]] = true
		seen[secrets["S3_ACCESS_KEY"]] = true
	}
}

func TestSecretSeedEnv(t *testing.T) {
	secrets := map[string]string{
		"DB_PASSWORD":   "dbpass123",
		"S3_ACCESS_KEY": "s3access",
		"S3_SECRET_KEY": "s3secret",
		"REDIS_PASSWORD": "redispass",
	}

	env := SecretSeedEnv("TEAM", "MYAPP", secrets)

	if !strings.Contains(env, "# TEAM/MYAPP - atlasctl seed") {
		t.Error("should contain group/app header")
	}
	if !strings.Contains(env, "VL_TEAM_MYAPP_DB_PASSWORD=dbpass123") {
		t.Error("should contain DB_PASSWORD entry")
	}
	if !strings.Contains(env, "VL_TEAM_MYAPP_S3_ACCESS_KEY=s3access") {
		t.Error("should contain S3_ACCESS_KEY entry")
	}
	if !strings.Contains(env, "VL_TEAM_MYAPP_S3_SECRET_KEY=s3secret") {
		t.Error("should contain S3_SECRET_KEY entry")
	}
	if !strings.Contains(env, "VL_TEAM_MYAPP_REDIS_PASSWORD=redispass") {
		t.Error("should contain REDIS_PASSWORD entry")
	}
}

func TestGenerateSeed_UnknownGenerator(t *testing.T) {
	keys := []config.SeedKey{
		{Name: "BAD", Generator: "unknown", Length: 16, EnvKey: "BAD"},
	}
	_, err := GenerateSeed(keys)
	if err == nil {
		t.Fatal("expected error for unknown generator")
	}
}
