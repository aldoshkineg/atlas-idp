// Package seed orchestrates database, object storage, and Vault provisioning for a workload.
package seed

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/k8s"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/vault"
)

type Workload struct {
	Group string
	App   string
	Dir   string
}

type Params struct {
	Workload
	DBPassword   string
	S3AccessKey  string
	S3SecretKey  string
	RedisPass    string
	ExtraSecrets map[string]string
	RawEnv       map[string]string
}

// MappingEntry describes a single vault write from seed-mapping.conf:
// which ENV var (from .secret-seed) to write to which vault path/key.
type MappingEntry struct {
	VaultPath string
	Key       string
	EnvVar    string
	DecodeB64 bool
}

// ParseMapping reads vault/seed-mapping.conf (optional). Each non-comment line
// has the form: <vault-path> <key>=<ENV_VAR_NAME>
// An ENV_VAR_NAME ending in _B64 means base64-decode the value before writing.
func ParseMapping(dir string) ([]MappingEntry, error) {
	file := filepath.Join(dir, "vault", "seed-mapping.conf")
	f, err := os.Open(file)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("open seed-mapping.conf: %w", err)
	}
	defer f.Close()

	var entries []MappingEntry
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		vaultPath := fields[0]
		kv := strings.SplitN(fields[1], "=", 2)
		if len(kv) != 2 {
			continue
		}
		key := kv[0]
		envVar := kv[1]
		decode := false
		if strings.HasSuffix(envVar, "_B64") {
			decode = true
		}
		entries = append(entries, MappingEntry{
			VaultPath: vaultPath,
			Key:       key,
			EnvVar:    envVar,
			DecodeB64: decode,
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read seed-mapping.conf: %w", err)
	}
	return entries, nil
}

type Service struct {
	k8s    *k8s.Client
	vault  *vault.Client
	cfg    *config.Config
}

func New(k8sClient *k8s.Client, vaultClient *vault.Client, cfg *config.Config) *Service {
	return &Service{k8s: k8sClient, vault: vaultClient, cfg: cfg}
}

func (s *Service) LoadParams(wl Workload) (*Params, error) {
	seedFile := filepath.Join(wl.Dir, ".secret-seed")
	if _, err := os.Stat(seedFile); err != nil {
		return nil, fmt.Errorf(".secret-seed not found: %w", err)
	}

	f, err := os.Open(seedFile)
	if err != nil {
		return nil, fmt.Errorf("open .secret-seed: %w", err)
	}
	defer f.Close()

	groupSafe := strings.ReplaceAll(wl.Group, "-", "_")
	appSafe := strings.ReplaceAll(wl.App, "-", "_")
	prefix := fmt.Sprintf("VL_%s_%s", strings.ToUpper(groupSafe), strings.ToUpper(appSafe))

	params := &Params{
		Workload:     wl,
		ExtraSecrets: make(map[string]string),
		RawEnv:       make(map[string]string),
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		name, value := parts[0], parts[1]
		params.RawEnv[name] = value
		if !strings.HasPrefix(name, prefix) {
			continue
		}
		suffix := strings.TrimPrefix(name, prefix+"_")
		switch suffix {
		case "DB_PASSWORD":
			params.DBPassword = value
		case "S3_ACCESS_KEY":
			params.S3AccessKey = value
		case "S3_SECRET_KEY":
			params.S3SecretKey = value
		case "REDIS_PASSWORD":
			params.RedisPass = value
		default:
			params.ExtraSecrets[suffix] = value
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read .secret-seed: %w", err)
	}

	return params, nil
}

func (s *Service) ValidateParams(p *Params) error {
	if p.DBPassword == "" {
		return fmt.Errorf("DB_PASSWORD is empty in .secret-seed")
	}
	if p.S3AccessKey == "" {
		return fmt.Errorf("S3_ACCESS_KEY is empty in .secret-seed")
	}
	if p.S3SecretKey == "" {
		return fmt.Errorf("S3_SECRET_KEY is empty in .secret-seed")
	}
	if p.RedisPass == "" {
		return fmt.Errorf("REDIS_PASSWORD is empty in .secret-seed")
	}
	return nil
}

func (s *Service) ProvisionDB(p *Params) error {
	dbName := p.App
	dbUser := p.App
	dbPod := "production-db-1"

	exists, err := s.k8s.PodExec("database", dbPod, "psql", "-t", "-c",
		fmt.Sprintf("SELECT 1 FROM pg_database WHERE datname='%s'", dbName))
	if err != nil {
		return fmt.Errorf("check db exists: %w", err)
	}

	if strings.TrimSpace(exists) == "1" {
		fmt.Printf("   Database '%s' already exists — skipping\n", dbName)
	} else {
		if _, err := s.k8s.PodExec("database", dbPod, "psql", "-c",
			fmt.Sprintf("CREATE DATABASE %s", dbName)); err != nil {
			return fmt.Errorf("create database: %w", err)
		}
		fmt.Printf("   Database '%s' created\n", dbName)
	}

	userExists, err := s.k8s.PodExec("database", dbPod, "psql", "-t", "-c",
		fmt.Sprintf("SELECT 1 FROM pg_roles WHERE rolname='%s'", dbUser))
	if err != nil {
		return fmt.Errorf("check user exists: %w", err)
	}

	if strings.TrimSpace(userExists) == "1" {
		fmt.Printf("   User '%s' already exists — updating password\n", dbUser)
		if _, err := s.k8s.PodExec("database", dbPod, "psql", "-c",
			fmt.Sprintf("ALTER USER %s WITH PASSWORD '%s'", dbUser, p.DBPassword)); err != nil {
			return fmt.Errorf("update user password: %w", err)
		}
	} else {
		fmt.Printf("   User '%s' created\n", dbUser)
		if _, err := s.k8s.PodExec("database", dbPod, "psql", "-c",
			fmt.Sprintf("CREATE USER %s WITH PASSWORD '%s'", dbUser, p.DBPassword)); err != nil {
			return fmt.Errorf("create user: %w", err)
		}
	}

	if _, err := s.k8s.PodExec("database", dbPod, "psql", "-c",
		fmt.Sprintf("GRANT ALL PRIVILEGES ON DATABASE %s TO %s", dbName, dbUser)); err != nil {
		return fmt.Errorf("grant db privileges: %w", err)
	}

	if _, err := s.k8s.PodExec("database", dbPod, "psql", "-d", dbName, "-c",
		fmt.Sprintf("GRANT ALL ON SCHEMA public TO %s", dbUser)); err != nil {
		return fmt.Errorf("grant schema privileges: %w", err)
	}

	return nil
}

func (s *Service) ProvisionS3(p *Params) error {
	minioNS := "minio"
	bucket := fmt.Sprintf("workloads/%s/%s", p.Group, p.App)

	minioPod, err := s.k8s.GetPodName(minioNS, "app=minio")
	if err != nil || minioPod == "" {
		minioPod = "minio-0"
	}

	rootUser, err := s.k8s.SecretReadDecoded(minioNS, "minio-auth", "rootUser")
	if err != nil {
		return fmt.Errorf("read minio root user: %w", err)
	}
	rootPass, err := s.k8s.SecretReadDecoded(minioNS, "minio-auth", "rootPassword")
	if err != nil {
		return fmt.Errorf("read minio root password: %w", err)
	}

	alias := "atlas-seed"
	s.k8s.PodExec(minioNS, minioPod, "mc", "alias", "set", alias,
		"http://localhost:9000", rootUser, rootPass)

	bucketCheck, _ := s.k8s.PodExec(minioNS, minioPod, "mc", "stat", alias+"/"+bucket)
	if bucketCheck != "" && !strings.Contains(bucketCheck, "does not exist") {
		fmt.Printf("   Bucket '%s' already exists — skipping\n", bucket)
	} else {
		if _, err := s.k8s.PodExec(minioNS, minioPod, "mc", "mb", alias+"/"+bucket); err != nil {
			return fmt.Errorf("create bucket: %w", err)
		}
		fmt.Printf("   Bucket '%s' created\n", bucket)
	}

	userList, _ := s.k8s.PodExec(minioNS, minioPod, "mc", "admin", "user", "list", alias)
	if strings.Contains(userList, p.S3AccessKey) {
		fmt.Printf("   MinIO user '%s' already exists — removing\n", p.S3AccessKey)
		s.k8s.PodExec(minioNS, minioPod, "mc", "admin", "user", "remove", alias, p.S3AccessKey)
	}

	if _, err := s.k8s.PodExec(minioNS, minioPod, "mc", "admin", "user", "add",
		alias, p.S3AccessKey, p.S3SecretKey); err != nil {
		return fmt.Errorf("create minio user: %w", err)
	}
	fmt.Printf("   MinIO user '%s' created\n", p.S3AccessKey)

	s.k8s.PodExec(minioNS, minioPod, "mc", "admin", "policy", "attach", alias,
		"readwrite", "--user", p.S3AccessKey)

	return nil
}

func (s *Service) WriteVault(p *Params) error {
	vaultPath := fmt.Sprintf("secret/workloads/%s/%s", p.Group, p.App)

	redisPass, err := s.k8s.SecretReadDecoded("redis", "redis-auth", "redis-password")
	if err != nil {
		return fmt.Errorf("read redis password: %w", err)
	}

	data := map[string]string{
		"db_username":    p.App,
		"db_password":    p.DBPassword,
		"db_host":        "production-db-rw.database.svc.cluster.local",
		"db_port":        "5432",
		"db_name":        p.App,
		"s3_access_key":  p.S3AccessKey,
		"s3_secret_key":  p.S3SecretKey,
		"s3_endpoint":    "http://minio.minio.svc.cluster.local:9000",
		"s3_bucket":      fmt.Sprintf("workloads/%s/%s", p.Group, p.App),
		"redis_password": redisPass,
		"redis_host":     "redis-master.redis.svc.cluster.local",
		"redis_port":     "6379",
	}

	for k, v := range p.ExtraSecrets {
		data[strings.ToLower(k)] = v
	}

	// Use seed-mapping.conf if present: it drives which vault paths/keys to write,
	// including multi-path entries (e.g. a separate cert path) and _B64 decoding.
	entries, err := ParseMapping(p.Dir)
	if err != nil {
		return err
	}
	if len(entries) > 0 {
		byPath := make(map[string]map[string]string)
		for _, e := range entries {
			value, ok := p.RawEnv[e.EnvVar]
			if !ok {
				return fmt.Errorf("mapping references undefined env var: %s", e.EnvVar)
			}
			if e.DecodeB64 {
				decoded, derr := base64.StdEncoding.DecodeString(value)
				if derr != nil {
					return fmt.Errorf("base64 decode %s: %w", e.EnvVar, derr)
				}
				value = string(decoded)
			}
			if byPath[e.VaultPath] == nil {
				byPath[e.VaultPath] = make(map[string]string)
			}
			byPath[e.VaultPath][e.Key] = value
		}
		for path, kv := range byPath {
			if err := s.vault.KVPut(path, kv); err != nil {
				return fmt.Errorf("write vault secrets to %s: %w", path, err)
			}
			fmt.Printf("   Secrets written to %s\n", path)
		}
		return nil
	}

	if err := s.vault.KVPut(vaultPath, data); err != nil {
		return fmt.Errorf("write vault secrets: %w", err)
	}
	fmt.Printf("   Secrets written to %s\n", vaultPath)
	return nil
}
