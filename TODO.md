# Atlas IDP — Implementation Roadmap

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

---

## Phase 0 — Repository & Tooling Baseline

- [x] Monorepo structure created (infra, gitops, apps, clusters, observability, vault, velero, security, docs)
- [x] `.gitignore`, `.yamllint.yml`, `.pre-commit-config.yaml` configured
- [x] Pre-commit hooks: trailing whitespace, YAML, Terraform fmt/validate, Trivy, key detection
- [x] `Makefile` with developer workflow targets
- [x] GitHub Actions self-hosted runner (Docker) operational
- [x] Fix structural inconsistencies:
  - [x] Remove `ci/` directory (replaced by `.github/workflows/`)
  - [x] Remove `assets/diagrams/` (duplicate of `docs/diagrams/`)
  - [x] Remove `infra/modules/cluster/` (superseded by `infra/modules/kind/`)
  - [x] Update Makefile `local-kind` references → `dev` (ENV defaults to `local-kind` but deploys to `infra/environments/dev`)
  - [x] Fix typo in `infra/modules/kind/variables.tf`: `v.1.35.0` → `v1.35.0`
  - [x] Create `gitops/platform/` directory layer (with ingress-nginx, cert-manager, metrics-server, monitoring)

---

## Phase 1 — Infrastructure Layer (Terraform)

- [x] `infra/modules/kind/` — kind cluster module (tehcyx/kind provider)
  - [x] Control-plane + N workers, ingress-ready label, port mappings
  - [x] Zot cache registry support via containerd config patch
  - [x] Outputs: endpoint, ca_cert, client_cert, client_key, kubeconfig_path
- [x] `infra/environments/dev/main.tf` — active dev environment wires kind module
- [x] `infra/environments/aws/` — stub + README (EKS planned)
- [x] AWS module stubs scaffolded: networking, iam, storage, addons, observability
- [x] `infra/modules/argocd-bootstrap/` — complete Terraform module (Day-0 Helm install)
  - [x] `main.tf`: `helm_release "argocd"` with proper values (NodePort, repo creds)
  - [x] `variables.tf`: kube credentials, argocd_version, repo_url, namespace
  - [x] `versions.tf`: helm ~> 2.14, kubernetes ~> 2.33
- [x] Wire `module "argocd_bootstrap"` into `infra/environments/dev/main.tf`
- [x] Wire `null_resource "argocd_root_app"` into `infra/environments/dev/main.tf`
- [ ] Terraform remote state (S3 backend stub for aws env)

---

## Phase 2 — Kubernetes Runtime

- [x] Cluster creation via Terraform `kind_cluster` resource (tehcyx/kind provider)
- [x] Validate `kind` + `kubectl` installed on self-hosted runner (runner image includes tools)

---

## Phase 3 — GitOps Layer (Argo CD) ← **CURRENT PRIORITY**

> **Status: ✅ COMPLETE — Day-0/Day-1 bootstrap implemented**

### Day-0: Argo CD Install (Terraform-driven)
- [x] `infra/modules/argocd-bootstrap/` — complete Terraform module with `helm_release` resource
  - [x] Namespace pre-creation via `kubernetes_namespace`
  - [x] `values.yaml` override: server NodePort, insecure mode for local, admin password BCrypt hash
  - [x] `depends_on = [module.kind_cluster]`
- [x] **Add Argo CD bootstrap step to GitHub Actions workflow `ci.yaml`**
  - [x] `kubectl wait --for=condition=available deploy/argocd-server -n argocd --timeout=180s`
  - [x] Smoke test: `kubectl get applications -n argocd`

### Day-1: App-of-Apps Root Application
- [x] `gitops/bootstrap/root-app.yaml` — root Application manifest exists
- [x] **Fix `repoURL`**: change `gitlab.com/example/atlas-idp.git` → actual GitHub repo URL
- [x] Create `gitops/platform/` layer with platform Application CRs:
  - [x] `gitops/platform/gateway-api.yaml`
  - [x] `gitops/platform/cert-manager.yaml`
  - [x] `gitops/platform/metrics-server.yaml`
  - [x] `gitops/platform/monitoring.yaml` (kube-prometheus-stack)
- [x] Apply root-app from Terraform (`null_resource` with kubectl)
- [x] Verify Argo CD self-heals on git push (automated sync + prune)

### Day-1+: Argo CD Self-Management
- [ ] `gitops/bootstrap/argocd/` — Argo CD manages its own helm release via Application CR (only README exists)
- [ ] ArgoCD Projects: `platform`, `workloads` (RBAC isolation)

---

## Phase 4 — Platform Services Layer

- [x] **gateway-api** — deployed via Argo CD (`gitops/platform/gateway-api.yaml`)
- [x] **cert-manager** — deployed via Argo CD, ClusterIssuer for local self-signed CA
- [x] **metrics-server** — deployed via Argo CD
- [x] **Prometheus + Grafana** (kube-prometheus-stack)
  - [x] `observability/alerts/custom-rule-1.yaml` — HighErrorRate (5xx > 5% for 5m)
  - [x] `observability/alerts/custom-rule-2.yaml` — HPAMaxedOut (HPA at max for 15m)
  - [x] Deploy via Argo CD Application
  - [x] Mount custom alert rules as ConfigMap via values override
  - [x] `observability/dashboards/` — Grafana dashboard JSON (platform overview)
- [x] **Loki + Alloy** — log aggregation stack, deployed via Argo CD
  - [x] Loki: SingleBinary mode, filesystem storage, 10d retention
  - [x] Alloy: DaemonSet collecting pod logs → loki-gateway
  - [x] Grafana: Loki datasource configured
- [x] **HashiCorp Vault**
  - [x] `vault/policies/platform-read.hcl` — read-only ACL for `secret/data/platform/*`
  - [x] `vault/kubernetes-auth/role-backend-api.yaml` — k8s auth role
  - [x] `vault/bootstrap/README.md`
  - [x] Vault deployed via Argo CD (`gitops/platform/layers/security/`)
  - [x] Vault init/unseal by Bank-Vaults operator (auto init + Shamir unseal)
  - [x] **Secrets injection via Bank-Vaults secrets-webhook v0.4.1**:
    - [x] Upgraded from old `vault-secrets-webhook` to `secrets-webhook` chart
    - [x] Webhook env: `PROVIDER=vault`, `VAULT_ADDR=http://vault.vault.svc:8200`, `VAULT_ALLOW_PRIVATE_ADDR=true`
    - [x] ClusterRoleBinding `vault-tokenreview` for K8s auth token validation
    - [x] File-based injection via vault-agent template (`vault-configmap` + `vault-agent-configmap`)
    - [x] Tested with `test-vault-inject` SA in `testing` namespace (secret read, file written)
    - [x] `security/vault-bootstrap.sh` — bootstrap script for seeding test secrets

---

## Phase 5 — CI/CD Layer (GitHub Actions)

- [x] `.github/workflows/ci.yaml` — Unified CI workflow with composite actions:
  - [x] `.github/actions/tools/` — Install terraform, kubectl, kind, trivy, yamllint
  - [x] `.github/actions/checks/` — terraform fmt/validate, yamllint, trivy config scan
  - [x] `.github/actions/terraform-kind/` — kind cluster + Argo CD bootstrap (init, plan, apply, verify)
  - [x] `.github/actions/terraform-eks/` — EKS stub (not implemented)
- [x] `.github/workflows/cleanup-local.yaml` — Manual KinD cluster cleanup workflow
- [x] Composite action architecture — reusable steps instead of separate workflow files
- [x] Cluster persists after apply (no auto-destroy)
- [x] Argo CD bootstrap verification step (wait for deployment, list applications)
- [x] `security.yml` — Trivy image scan on `apps/**` changes
- [ ] Add `workflow_dispatch` inputs to `ci.yaml`: `action: apply|destroy`, `environment: dev|staging`

---

## Phase 6 — Security Baseline

- [x] `security/trivy/trivy.yaml` — Trivy config (HIGH/CRITICAL, IaC scan)
- [ ] `security/rbac/` — RBAC policies (only `.gitkeep` exists)
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

## Next Sprint Focus

```
Phase 4 — Platform Services Completion

1. [DONE]    Mount custom Prometheus alert rules as ConfigMap via values override
2. [DONE]    Create Grafana dashboard JSON (platform overview)
3. [DONE]      Deploy Loki + Alloy via Argo CD for log aggregation
4. [DONE]      Vault deployed via Argo CD (Bank-Vaults operator), init/unseal automatic
5. [DONE]      Vault Agent injection via secrets-webhook (file-based, vault-agent template)
6. [NEXT]      Begin Phase 7: Workload services (backend-api, worker)
```
