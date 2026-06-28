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

| Directory                 | Purpose                                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `infra/`                  | Terraform IaC - environments (dev/aws) and reusable modules (kind, argocd-bootstrap, networking, iam, storage) |
| `gitops/`                 | Argo CD manifests - bootstrap (root app), platform (platform services), workloads (planned)                    |
| `gitops/platform/layers/` | Platform layer configurations with values overrides                                                            |
| `clusters/`               | kind cluster configs, scripts for create/destroy/bootstrap                                                     |
| `observability/`          | Prometheus alert rules, Grafana dashboards (planned)                                                           |
| `vault/`                  | Vault policies, Kubernetes auth roles, bootstrap scripts                                                       |
| `security/`               | Trivy config, RBAC policies (planned)                                                                          |
| `.github/`                | GitHub Actions workflows and composite actions                                                                 |
| `apps/`                   | Seal project                                                                                                   |
| `tools/atlasctl/`         | Go CLI for workload lifecycle management (scaffold, seed, enable, disable, status, list)                       |

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
- **MinIO:** bucket `cnpg-backups`, endpoint `http://minio.minio.svc.cluster.local:9000`, creds `minioadmin`/`minioadminpassword`
- **Next commit removes** all backup CRs from gitops; infra cluster will run as plain PostgreSQL without plugins.

### Seal Project

- **Repo:** `aldoshkineg/atlas-dip` (extracted; ArgoCD Application in `gitops/workloads/layers/seal/seal.yaml` points there)
- **Images on GHCR:** `ghcr.io/aldoshkineg/seal-{api,worker,ui}` — all three have `v0.25.0` and `0.2.0-alpha`; seal-api/seal-worker also have `latest`
- **Build:** `go-task -t apps/seal/Taskfile.yml build-all` (local `docker buildx`), `push-images` (tag `:dev` → `ghcr.io/aldoshkineg/*:v0.25.0` + push)
- **CI workflow:** `.github/workflows/seal-docker-publish.yml` — triggers on push main/push tag `v*`/PR main; uses `type=ref,event=tag` preserving `v` prefix
- **act issues:** parallel matrix jobs fail (Docker context canceled); use `go-task act-build` for sequential builds
- **Task CLI:** `task` a distrobox wrapper — use `go-task` directly
- **Credentials in `.env`:** `GITHUB_TOKEN=ghp_...` (repo, workflow, write:packages, delete:packages)

### atlasctl (Go CLI)

- **Location:** `tools/atlasctl/` — standalone Go module (`go.mod` at `tools/atlasctl/go.mod`)
- **Module path:** `github.com/aldoshkineg/atlas-idp/tools/atlasctl`
- **CLI framework:** Cobra (github.com/spf13/cobra v1.10+)
- **Commands:** `new`, `seed`, `enable`, `disable`, `delete`, `status`, `list`, `logs`, `backup`
- **Build:** `go-task -t tools/atlasctl/Taskfile.yml build` → binary at `tools/atlasctl/bin/atlasctl`
- **Test:** `go-task -t tools/atlasctl/Taskfile.yml test`
- **Vet:** `go-task -t tools/atlasctl/Taskfile.yml vet`
- **Coverage:** `go-task -t tools/atlasctl/Taskfile.yml cover`
- **Clean:** `go-task -t tools/atlasctl/Taskfile.yml clean`
- **Package structure:**
  ```
  tools/atlasctl/
  ├── main.go              # Entry point → cmd.Execute()
  ├── cmd/                 # Cobra command implementations
  │   ├── root.go          # Root command (--help, --version)
  │   ├── new.go / seed.go / enable.go / disable.go / delete.go
  │   └── status.go / list.go / logs.go / backup.go
  ├── pkg/
  │   ├── template/        # Template rendering (templates/gold/)
  │   ├── seed/            # DB/S3/Vault provisioning
  │   ├── gitops/          # GitOps file management
  │   ├── k8s/             # Kubernetes client wrapper
  │   ├── vault/           # Vault API client
  │   └── gateway/         # Gateway resource management
  ├── go.mod / go.sum
  ├── Taskfile.yml
  └── .gitignore
  ```
- **Current status:** all 9 commands implemented (new, seed, enable, disable, delete, status, list, logs, backup); all tests green
- **Release:** `git tag vX.Y.Z && git push origin vX.Y.Z` triggers `.github/workflows/atlasctl-release.yml` — builds for linux/darwin (amd64+arm64), injects version via `-ldflags "-X github.com/aldoshkineg/atlas-idp/tools/atlasctl/cmd.Version=vX.Y.Z"`, publishes to GitHub Release
- **Version:** `cmd/root.go` has `var Version = "dev"` — overridden by ldflags at release build
- **Build artifacts excluded via** `tools/atlasctl/.gitignore` (bin/, go.work, _.test, _.out, \*.cov, coverage/)

- 3 pods: `seal-api`, `seal-worker`, `seal-ui` — all running with `ghcr.io/aldoshkineg/*:v0.25.0`
- **seal-api** exposed on 8080; needs Postgres (`production-db-rw.database.svc:5432`, user `app`/`MyzuMb6...`), Redis (`redis-master.redis.svc:6379`, pw `e5f2190c...`), MinIO (`minio.minio.svc:9000`, admin creds from Vault)
- **seal-worker** needs Redis + MinIO
- **seal-ui** exposed on 3000; no env vars
