// Package seed orchestrates database, object storage, and Vault provisioning for a workload.
package seed

import (
	"bufio"
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
		"db_username":   p.App,
		"db_password":   p.DBPassword,
		"db_host":       "production-db-rw.database.svc.cluster.local",
		"db_port":       "5432",
		"db_name":       p.App,
		"s3_access_key": p.S3AccessKey,
		"s3_secret_key": p.S3SecretKey,
		"s3_endpoint":   "http://minio.minio.svc.cluster.local:9000",
		"s3_bucket":     fmt.Sprintf("workloads/%s/%s", p.Group, p.App),
		"redis_password": redisPass,
		"redis_host":    "redis-master.redis.svc.cluster.local",
		"redis_port":    "6379",
	}

	for k, v := range p.ExtraSecrets {
		data[strings.ToLower(k)] = v
	}

	if err := s.vault.KVPut(vaultPath, data); err != nil {
		return fmt.Errorf("write vault secrets: %w", err)
	}
	fmt.Printf("   Secrets written to %s\n", vaultPath)
	return nil
}
