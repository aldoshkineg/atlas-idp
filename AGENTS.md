# Repository Overview

## Project Description
Atlas IDP is a production-grade Internal Developer Platform (IDP) monorepo demonstrating end-to-end platform engineering with:
- Infrastructure as Code (IaC) using Terraform/OpenTofu
- GitOps delivery via Argo CD (app-of-apps pattern)
- CI/CD automation with GitHub Actions
- Observability stack (Prometheus, Grafana, Loki)
- Secrets management with HashiCorp Vault
- Security scanning (Trivy, yamllint, pre-commit hooks)
- Disaster recovery foundation with Velero

The platform runs locally on kind Kubernetes clusters while following AWS production patterns.

## Architecture Overview
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  GitHub Repo    │────▶│  GitHub Actions │────▶│ kind Kubernetes │
│  (IaC + GitOps) │     │  (CI/CD)        │     │  Cluster        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Terraform      │────▶│  Argo CD        │────▶│ Platform        │
│  (infra/)       │     │  (gitops/)      │     │ Services        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Key Components:**
- **Infrastructure Layer** (`infra/`): Terraform modules for kind cluster, Argo CD bootstrap
- **GitOps Layer** (`gitops/`): App-of-Apps pattern with root application managing platform services
- **Platform Services**: gateway-api, cert-manager, metrics-server, monitoring (kube-prometheus-stack)
- **Observability**: Custom Prometheus alert rules, Grafana dashboards (planned)
- **Security**: Vault policies, Trivy scanning, pre-commit hooks

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `infra/` | Terraform IaC - environments (dev/aws) and reusable modules (kind, argocd-bootstrap, networking, iam, storage) |
| `gitops/` | Argo CD manifests - bootstrap (root app), platform (platform services), workloads (planned) |
| `gitops/platform/layers/` | Platform layer configurations with values overrides |
| `clusters/` | kind cluster configs, scripts for create/destroy/bootstrap |
| `observability/` | Prometheus alert rules, Grafana dashboards (planned) |
| `vault/` | Vault policies, Kubernetes auth roles, bootstrap scripts |
| `security/` | Trivy config, RBAC policies (planned) |
| `.github/` | GitHub Actions workflows and composite actions |
| `apps/` | Sample applications (backend-api, worker, cronjob - planned) |

**Key Files:**
- `infra/environments/dev/main.tf` - Main Terraform entry point for dev environment
- `gitops/bootstrap/root-app.yaml` - Root Application for app-of-apps pattern
- `Makefile` - Developer workflow commands
- `.pre-commit-config.yaml` - Pre-commit hook configuration

## Development Workflow

### Prerequisites
- kind v0.26+, kubectl v1.31+, Terraform v1.9+
- Docker, pre-commit, yamllint, Trivy

### Build & Deploy
```bash
# Create kind cluster
make cluster-up

# Deploy infrastructure (creates cluster + Argo CD)
make infra-apply

# Validate all changes
make validate

# Run pre-commit hooks
make pre-commit
```

### Access Argo CD
```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Port forward to access UI at http://localhost:30080
kubectl port-forward -n argocd svc/argocd-server 30080:80
```

### Cleanup
```bash
make cluster-nuke  # Force delete cluster and wipe tfstate
```

### Testing
- Terraform: `terraform fmt -check -recursive infra/`, `terraform validate`
- YAML: `yamllint -c .yamllint.yml gitops/ observability/ security/`
- Security: `trivy config --severity HIGH,CRITICAL infra/ gitops/`

## Code Standards

### YAML Formatting
- Line length max 140 (warning level)
- Document-start disabled
- truthy check-keys disabled

### Terraform
- Use `terraform fmt` before committing
- All modules must have `versions.tf` with explicit provider constraints

### Git Hooks
Pre-commit runs on every commit:
- Trailing whitespace, end-of-file fixer
- YAML validation
- Terraform fmt/validate/docs
- yamllint
- Trivy (HIGH/CRITICAL only)

## Session Context

### CNPG / PostgreSQL Cluster State (June 2026)
- **Cluster:** `production-db` in `database` namespace, 1 instance, PG 17.6, csi-hostpath-sc
- **Operator:** cloudnative-pg 0.28.3 (app 1.29.1) in `cnpg-system`, `INCLUDE_PLUGINS: barman-cloud.cloudnative-pg.io`
- **Backup config moved to** `examples/cnpg-backup/` (ObjectStore + Secret + ScheduledBackup)
- **Current running cluster** (`kubectl get cluster -n database production-db -o json`):
  ```json
  "spec": {
    "plugins": [{
      "enabled": true,
      "isWALArchiver": true,
      "name": "barman-cloud.cloudnative-pg.io",
      "parameters": {"barmanObjectName": "production-db-backup"}
    }]
  }
  ```
  ObjectStore `production-db-backup`, Secret `production-db-backup`, ScheduledBackup `production-db-weekly` — recreated by ArgoCD from git HEAD, pending cleanup commit.
- **MinIO:** bucket `cnpg-backups`, endpoint `http://minio.minio.svc.cluster.local:9000`, creds `minioadmin`/`minioadminpassword`
- **Next commit removes** all backup CRs from gitops; infra cluster will run as plain PostgreSQL without plugins.

### Task Runner
- `task` on this system is **taskwarrior** (task manager), NOT go-task.
- Use **`go-task`** (binary at `~/.local/bin/task`) for `Taskfile.yml` commands.
- If `go-task` is not on PATH, invoke via full path: `~/.local/bin/task`.
- Example: `go-task dc-ps`, `go-task dc-up`, `go-task test`.
- Taskfile.yml is at `apps/Taskfile.yml`. Run from repo root with `go-task -f apps/Taskfile.yml <target>` or `cd apps && go-task <target>`.

### text2pdf Architecture (June 2026)
- **Worker** is a blind PDF factory: reads JSON `{document_id, input_text}` from Redis `text2pdf:jobs`, generates PDF, signs, uploads to MinIO, writes `{document_id, status, s3_path, error}` to `text2pdf:results`. **No PostgreSQL access.**
- **Backend API** owns PostgreSQL and Redis job queue. Pushes JSON jobs to `text2pdf:jobs` (with `input_text`), background goroutine consumes `text2pdf:results` and updates PG document status. **No MinIO client** (download URL constructed from config prefix).
- Verify endpoint (`/api/v1/documents/{id}/verify`) checks PG status — returns `valid: true` if status is `completed`.
- Job flow: `POST /documents` → PG insert + Redis `text2pdf:jobs` → Worker reads → signs → uploads → Redis `text2pdf:results` → Backend-API consumer updates PG status

### PDF Signing (June 2026)
- Worker signs every PDF with `digitorus/pdfsign` (CMS/PAdES, RSA 2048, SHA-256)
- Signing cert paths configured via `SIGN_CERT_PATH` / `SIGN_KEY_PATH` env vars
- Dev defaults point to Vault Agent paths (`/vault/secrets/tls.{crt,key}`)
- Local dev: `go-task gen-certs` generates self-signed cert to `apps/.certs/tls.{crt,key}`
- Docker Compose mounts `apps/.certs/` into the worker container
- **Production:** key stored in Vault (`kv/data/text2pdf/pdf-signer`), injected via Vault Agent
- **Dev:** `.certs/` is gitignored; certs generated via `go-task gen-certs`
- Metrics: `pdf_sign_duration_seconds`, `pdf_sign_errors_total`

### Infra Tests (June 2026)
- Full stack smoke tests: `cd apps/tests/integration && ./test-infra.sh`
- Tests: postgres, redis, minio, API healthz/readyz, document CRUD, worker processing, MinIO PDF existence, worker metrics, signature verification
- Docker Compose stack: `apps/tests/integration/docker-compose.yml`
- Secrets: `apps/tests/integration/.env` (not committed)
