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

The platform runs locally on a Talos Linux Kubernetes cluster provisioned on Incus VMs, following production patterns.

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  GitHub Repo    │────▶│  GitHub Actions │────▶│ Talos Kubernetes │
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

- **Infrastructure Layer** (`infra/`): Terraform modules for Talos/Incus cluster, Argo CD bootstrap
- **GitOps Layer** (`gitops/`): App-of-Apps pattern with root application managing platform services
- **Platform Services**: gateway-api, cert-manager, metrics-server, monitoring (kube-prometheus-stack), KEDA (event-driven autoscaling), Redis (cache/broker)
- **Observability**: Prometheus alert rules, Grafana dashboards, Loki
- **Security**: Vault policies, Trivy scanning, network policies, pre-commit hooks

## Directory Structure

| Directory                 | Purpose                                                                            |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `infra/`                  | Terraform IaC — environments (stage) and reusable modules                          |
| `gitops/`                 | Argo CD manifests — bootstrap (root app), platform layers, workloads (tenant apps) |
| `gitops/platform/layers/` | Platform layer configurations with values overrides                                |
| `workloads/`              | Tenant workload definitions managed by atlasctl (single source of truth)           |
| `templates/gold/`         | Golden-path templates (`.tmpl`) used by atlasctl to scaffold new workloads         |
| `recipes/`                | Standalone cluster snippets applied manually with kubectl (outside GitOps)         |
| `apps/`                   | Source projects (e.g. seal): code, Helm charts, per-app tests                      |
| `tools/vault/`            | Vault policies, Kubernetes auth roles, bootstrap scripts                           |
| `security/`               | CA certs, RBAC, Trivy config, Cosign keys                                          |
| `tests/`                  | Platform-level e2e suites and runners (`tests/scripts/*.sh`)                       |
| `.github/`                | GitHub Actions workflows and composite actions                                     |
| `tools/atlasctl/`         | Go CLI for workload lifecycle management                                           |

See `docs/tech-stack.md` for the technology inventory and `docs/setup.md` for the getting-started guide.

**Key Files:**

- `infra/environments/stage/main.tf` - Main Terraform entry point for the stage environment
- `gitops/bootstrap/root-app.yaml` - Root Application for app-of-apps pattern
- `Makefile` - Developer workflow commands
- `.pre-commit-config.yaml` - Pre-commit hook configuration

## Development Workflow

### Prerequisites

- talosctl v1.34+, kubectl v1.31+, Terraform v1.9+
- Docker, pre-commit, yamllint, Trivy

### Build & Deploy

```bash
# Deploy the base stage (Terraform + Vault seeds) via act.
# Terraform is driven through act, not a standalone Make target.
make act-stage-base

# Sync platform layers (DB/MinIO/Vault/monitoring) via act
make act-stage-middleware

# Seed + sync workloads (seal) via act
make act-stage-workload

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
make act-destroy   # Destroy the stage (Incus/Talos) infrastructure
```

### Testing

- Terraform: `terraform fmt -check -recursive infra/`, `terraform validate`
- YAML: `yamllint -c .yamllint.yml gitops/ security/`
- Security: `trivy config --severity HIGH,CRITICAL infra/ gitops/`
- Platform e2e: `make test` (suites under `tests/`, runners in `tests/scripts/`)

## Code Standards

### YAML Formatting

- Line length max 140 (warning level)
- Document-start disabled
- truthy check-keys disabled

### Terraform

- Use `terraform fmt` before committing
- All modules must have `versions.tf` with explicit provider constraints

### Commit Messages

- Use Conventional Commits with a scope in parentheses: `feat(scope):`, `fix(scope):`, `refactor(scope):`, `chore(scope):`, etc.
- **Do NOT add `Co-Authored-By`, `Generated-with`, or any similar AI/tool trailer lines unless the user explicitly asks for them.** Keep commit messages clean and authored by the user. The AI assistant (`opencode`) must never append such trailers.
- **NEVER run `git commit` (or `git add` + `git commit`) without the user's explicit approval for that specific change — including fix commits made while troubleshooting.** Editing files is allowed; committing is not. When in doubt, ask first.
- Never amend, rebase, or force-push without explicit request.

### Git Hooks

Pre-commit runs on every commit:

- Trailing whitespace, end-of-file fixer
- YAML validation
- Terraform fmt/validate/docs
- yamllint
- Trivy (HIGH/CRITICAL only)
