# Atlas IDP — Implementation Roadmap

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

---

## Phase 0 — Repository & Tooling Baseline

- [x] Monorepo structure created (infra, gitops, apps, clusters, observability, vault, velero, security, docs)
- [x] `.gitignore`, `.yamllint.yml`, `.pre-commit-config.yaml` configured
- [x] Pre-commit hooks: trailing whitespace, YAML, Terraform fmt/validate, Trivy, key detection
- [x] `Makefile` with developer workflow targets
- [x] GitHub Actions self-hosted runner (Docker) operational
- [ ] Fix structural inconsistencies:
  - [ ] Remove `ci/` directory (replaced by `.github/workflows/`)
  - [ ] Remove `assets/diagrams/` (duplicate of `docs/diagrams/`)
  - [ ] Remove `infra/modules/cluster/` (superseded by `infra/modules/kind/`)
  - [ ] Rename `infra/environments/local-kind/` refs in Makefile → `dev`
  - [ ] Fix typo in `infra/modules/kind/variables.tf`: `v.1.35.0` → `v1.35.0`
  - [ ] Create `gitops/platform/` directory layer (currently missing between root-app and workloads)

---

## Phase 1 — Infrastructure Layer (Terraform)

- [x] `infra/modules/kind/` — kind cluster module (tehcyx/kind provider)
  - [x] Control-plane + N workers, ingress-ready label, port mappings
  - [x] Zot cache registry support via containerd config patch
  - [x] Outputs: endpoint, ca_cert, client_cert, client_key, kubeconfig_path
- [x] `infra/environments/dev/main.tf` — active dev environment wires kind module
- [x] `infra/environments/aws/` — stub + README (EKS planned)
- [x] AWS module stubs scaffolded: networking, iam, storage, addons, observability
- [ ] `infra/modules/argocd-bootstrap/` — **refactor from `infra/bootstrap/argocd/`**
  - [ ] `main.tf`: `helm_release "argocd"` with proper values (NodePort, repo creds)
  - [ ] `variables.tf`: kube credentials, argocd_version, repo_url, namespace
  - [ ] `versions.tf`: helm ~> 2.14, kubernetes ~> 2.33
- [ ] Wire `module "argocd_bootstrap"` into `infra/environments/dev/main.tf`
- [ ] Wire `kubernetes_manifest "argocd_root_app"` into `infra/environments/dev/main.tf`
- [ ] Terraform remote state (S3 backend stub for aws env)

---

## Phase 2 — Kubernetes Runtime

- [x] `clusters/kind/cluster.yaml` — 1 CP + 2 workers, ingress ports 80/443
- [x] `clusters/kind/cluster-ci.yaml` — lightweight CI variant (1 CP + 1 worker)
- [ ] `clusters/scripts/create-cluster.sh` — create cluster via kind CLI
- [ ] `clusters/scripts/destroy-cluster.sh` — delete cluster
- [ ] `clusters/scripts/bootstrap-gitops.sh` — post-cluster: terraform apply → root-app apply
- [ ] Validate `kind` + `kubectl` installed on self-hosted runner

---

## Phase 3 — GitOps Layer (Argo CD) ← **CURRENT PRIORITY**

> **Status: 🔴 IN PROGRESS — Day-0 bootstrap under active implementation**

### Day-0: Argo CD Install (Terraform-driven)
- [~] `infra/bootstrap/argocd/main.tf` exists but incomplete (missing `helm_release` resource)
- [ ] **Complete `helm_release "argocd"` in `infra/modules/argocd-bootstrap/main.tf`**
  - [ ] Namespace pre-creation via `kubernetes_namespace`
  - [ ] `values.yaml` override: server NodePort, insecure mode for local, admin password BCrypt hash
  - [ ] `depends_on = [module.kind_cluster]`
- [ ] **Add Argo CD bootstrap step to GitHub Actions workflow `terraform.yml`**
  - [ ] `kubectl wait --for=condition=available deploy/argocd-server -n argocd --timeout=120s`
  - [ ] Smoke test: `kubectl get applications -n argocd`

### Day-1: App-of-Apps Root Application
- [x] `gitops/bootstrap/root-app.yaml` — root Application manifest exists
- [ ] **Fix `repoURL`**: change `gitlab.com/example/atlas-idp.git` → actual GitHub repo URL
- [ ] Create `gitops/platform/` layer with platform Application CRs:
  - [ ] `gitops/platform/ingress-nginx.yaml`
  - [ ] `gitops/platform/cert-manager.yaml`
  - [ ] `gitops/platform/metrics-server.yaml`
  - [ ] `gitops/platform/monitoring.yaml` (kube-prometheus-stack)
- [ ] Apply root-app from Terraform (`kubernetes_manifest`) or post-apply script
- [ ] Verify Argo CD self-heals on git push (automated sync + prune)

### Day-1+: Argo CD Self-Management
- [ ] `gitops/bootstrap/argocd/` — Argo CD manages its own helm release via Application CR
- [ ] ArgoCD Projects: `platform`, `workloads` (RBAC isolation)

---

## Phase 4 — Platform Services Layer

- [ ] **ingress-nginx** — deployed via Argo CD (`gitops/platform/ingress-nginx.yaml`)
- [ ] **cert-manager** — deployed via Argo CD, ClusterIssuer for local self-signed CA
- [ ] **metrics-server** — deployed via Argo CD
- [ ] **Prometheus + Grafana** (kube-prometheus-stack)
  - [x] `observability/alerts/custom-rule-1.yaml` — HighErrorRate (5xx > 5% for 5m)
  - [x] `observability/alerts/custom-rule-2.yaml` — HPAMaxedOut (HPA at max for 15m)
  - [ ] Deploy via Argo CD Application
  - [ ] Mount custom alert rules as ConfigMap via values override
  - [ ] `observability/dashboards/` — Grafana dashboard JSON (platform overview)
- [ ] **Loki** — log aggregation, deployed via Argo CD
- [ ] **HashiCorp Vault**
  - [x] `vault/policies/platform-read.hcl` — read-only ACL for `secret/data/platform/*`
  - [x] `vault/kubernetes-auth/role-backend-api.yaml` — k8s auth role
  - [x] `vault/bootstrap/README.md`
  - [ ] Vault deployed via Argo CD (`gitops/platform/vault.yaml`)
  - [ ] Vault init/unseal bootstrap script (`vault/bootstrap/init.sh`)
  - [ ] Vault Agent Injector tested with `backend-api` service account

---

## Phase 5 — CI/CD Layer (GitHub Actions)

- [x] `.github/workflows/terraform.yml` — Terraform deploy: kind lifecycle
- [x] `.github/workflows/tests.yml` — fmt check, validate, yamllint, trivy
- [ ] Split workflow concerns:
  - [ ] `validate.yml` — PR gate: terraform fmt/validate, yamllint, trivy config scan
  - [ ] `deploy.yml` — push to main: terraform apply (cluster + argocd bootstrap)
  - [ ] `destroy.yml` — scheduled or manual: terraform destroy
- [ ] Remove `terraform destroy` from deploy workflow `if: always()` — currently destroys cluster immediately after create
- [ ] Add Argo CD bootstrap verification step to deploy workflow
- [ ] `security.yml` — Trivy image scan on `apps/**` changes
- [ ] Add `workflow_dispatch` inputs: `action: apply|destroy`, `environment: dev|staging`

---

## Phase 6 — Security Baseline

- [x] `security/trivy/trivy.yaml` — Trivy config (HIGH/CRITICAL, IaC scan)
- [ ] `security/rbac/` — RBAC policies
  - [ ] `platform-admin` ClusterRole (full platform namespace access)
  - [ ] `workload-deployer` Role (deploy-only to workload namespaces)
  - [ ] `readonly` ClusterRole for observability service accounts
- [ ] Network Policies — namespace isolation (deny-all default, allow ingress/monitoring)
- [ ] Pod Security Standards — `restricted` profile for workload namespaces
- [ ] Trivy Operator deployed in-cluster (continuous scanning)

---

## Phase 7 — Workloads Layer

- [ ] **backend-api** (Go or Python)
  - [ ] Dockerfile (multi-stage, non-root user)
  - [ ] Helm chart (`apps/charts/backend-api/`)
  - [ ] Kubernetes manifests: Deployment, Service, HPA, PodDisruptionBudget
  - [ ] Liveness / Readiness / Startup probes
  - [ ] Resource limits/requests defined
  - [ ] Vault Agent sidecar for secret injection
- [ ] **worker** service — same checklist as backend-api
- [ ] **cronjob** — CronJob manifest with concurrencyPolicy, backoffLimit
- [ ] Argo CD `Application` CRs for each workload in `gitops/workloads/`
- [ ] Image build pipeline: GitHub Actions → push to registry (ghcr.io or local zot)

---

## Phase 8 — Disaster Recovery (Velero)

- [ ] `velero/` — Velero configuration
  - [ ] `velero/install/` — Helm values for Velero deployment
  - [ ] `velero/schedules/` — BackupSchedule CRs (daily platform namespaces)
  - [ ] `velero/restore/` — Restore procedure + tested runbook
- [ ] Deploy Velero via Argo CD (`gitops/platform/velero.yaml`)
- [ ] Backup storage: MinIO (local kind) / S3 (AWS)
- [ ] DR runbook: `docs/runbooks/disaster-recovery.md`
  - [ ] Scenario: cluster total loss → restore from backup
  - [ ] RTO/RPO targets documented

---

## Phase 9 — Documentation & AWS Readiness

- [ ] `docs/architecture.md` — layered system overview + decision log
- [ ] `docs/diagrams/` — draw.io / Mermaid architecture diagrams
  - [ ] Platform overview (layers)
  - [ ] GitOps flow (git push → Argo CD sync → k8s)
  - [ ] Secrets flow (Vault → workload)
- [ ] `docs/runbooks/argocd-bootstrap.md`
- [ ] `docs/runbooks/vault-init.md`
- [ ] `docs/runbooks/disaster-recovery.md`
- [ ] AWS environment plan:
  - [ ] EKS module (`infra/modules/eks/`)
  - [ ] IRSA roles module (`infra/modules/iam/`)
  - [ ] S3 Terraform state backend
  - [ ] Migration path: local-kind → EKS (same gitops/ layer, only infra changes)

---

## Current Sprint Focus

```
Phase 3 — Argo CD Day-0 Bootstrap

1. [IMMEDIATE] Complete infra/modules/argocd-bootstrap/main.tf (helm_release)
2. [IMMEDIATE] Wire module into infra/environments/dev/main.tf
3. [IMMEDIATE] Fix root-app.yaml repoURL (gitlab → github)
4. [NEXT]      Create gitops/platform/ layer with first Applications (ingress-nginx, cert-manager)
5. [NEXT]      Update GitHub Actions terraform.yml: add argocd readiness check, remove auto-destroy
```
