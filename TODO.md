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
  - [x] Update Makefile `local-kind` references → `dev`
  - [x] Fix typo in `infra/modules/kind/variables.tf`: `v.1.35.0` → `v1.35.0`
  - [x] Create `gitops/` structure (`platform-kind/`, `workloads/`, `bootstrap/`)

---

## Phase 1 — Infrastructure Layer (Terraform)

- [x] `infra/modules/kind/` — kind cluster module (tehcyx/kind provider)
  - [x] Control-plane + N workers, ingress-ready label, port mappings
  - [x] Zot cache registry support via containerd config patch (`enable_cache = true`)
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
- [x] Terraform remote state (S3 backend stub for aws env)

---

## Phase 2 — Kubernetes Runtime

- [x] Cluster creation via Terraform `kind_cluster` resource (tehcyx/kind provider)
- [x] Validate `kind` + `kubectl` installed on self-hosted runner

---

## Phase 3 — GitOps Layer (Argo CD)

> Day-0 and Day-1 bootstrap implemented. 20 applications deployed and synced.

### Day-0: Argo CD Install (Terraform-driven)
- [x] `infra/modules/argocd-bootstrap/` — complete Terraform module with `helm_release` resource
  - [x] Namespace pre-creation via `kubernetes_namespace`
  - [x] `values.yaml` override: server NodePort, insecure mode for local, admin password BCrypt hash
  - [x] `depends_on = [module.kind_cluster]`
- [x] Argo CD bootstrap step in `.github/workflows/ci.yaml`
  - [x] `kubectl wait --for=condition=available deploy/argocd-server -n argocd --timeout=180s`
  - [x] Smoke test: `kubectl get applications -n argocd`

### Day-1: App-of-Apps Root Application
- [x] `gitops/bootstrap/root-app.yaml` — root Application manifest
- [x] `repoURL` points to actual GitHub repo
- [x] Root-app auto-discovers child Application CRs under `gitops/platform-kind/layers/`
- [x] Sync-waves 0-7 configured across all child apps
- [x] Zot pull-through cache running (`kind-zot-registry:5000`, 9.9GB cached, 571 blobs)
- [x] Apply root-app from Terraform (`null_resource` with kubectl)
- [x] Verify Argo CD self-heals on git push (automated sync + prune)

### Day-1+: Argo CD Self-Management
- [x] Root-app renamed `root-platform` → `root-app`, converted to multi-source (`platform-kind/layers/` + `workloads/layers/`)
- [x] ArgoCD Project `platform-kind` — restricts platform apps to their namespaces (sync-wave -1)
- [x] ArgoCD Project `workloads` — restricts workload apps to backend-api, worker, cronjob (sync-wave -1), cluster-resources disabled
- [x] All 19 child Application CRs migrated: `project: default` → `project: platform-kind`
- [x] `gitops/workloads/layers/` — scaffold directory ready for future workloads

---

## Phase 4 — Platform Services Layer

### Networking
- [x] **gateway-api-crds** — deployed (sync-wave 0)
- [x] **nginx-gateway-fabric** — deployed (sync-wave 2)
- [x] **gateway-resources** — HTTPRoute for nginx deployed (sync-wave 4)
- [x] **Ingress gateways** — grafana-gateway, vault-gateway, minio-gateway deployed (sync-wave 6)

### Security
- [x] **cert-manager** — deployed (sync-wave 0)
- [x] **cert-manager-issuers** — ClusterIssuer for local self-signed CA (sync-wave 1)
- [x] **vault-operator** — deployed via Bank-Vaults (sync-wave 0)
- [x] **vault** — 3/3 pods running, init/unseal automatic
- [x] **vault-secrets-webhook** — secrets injection via Bank-Vaults v0.4.1
  - [x] `PROVIDER=vault`, `VAULT_ADDR=http://vault.vault.svc:8200`
  - [x] ClusterRoleBinding `vault-tokenreview` for K8s auth
  - [x] File-based injection via vault-agent template
  - [x] Tested with `test-vault-inject` SA in `testing` namespace
  - [x] `security/vault-bootstrap.sh` — bootstrap script
  - [ ] **HPA broken**: missing `resources.requests.cpu` in container `secrets-webhook`

### Storage
- [x] **snapshot-crds** — VolumeSnapshot CRDs (sync-wave 1)
- [x] **snapshot-controller** — CSI Snapshot controller (sync-wave 2)
- [x] **csi-hostpath** — CSI driver for local persistent volumes (sync-wave 3)
- [x] **minio** — S3-compatible object storage (sync-wave 3)
- [x] **velero** — backup/restore, backed by MinIO (sync-wave 4)

### Base
- [x] **metrics-server** — deployed (sync-wave 1)

### Observability
- [x] **kube-prometheus-stack** — Prometheus + Grafana + Alertmanager (sync-wave 5)
  - [x] Custom alert rules: HighErrorRate, HPAMaxedOut — mounted as ConfigMap
  - [x] Grafana dashboard JSON (platform overview) in `observability/dashboards/`
- [x] **loki** — SingleBinary mode, filesystem storage, 10d retention (sync-wave 6)
- [x] **alloy** — DaemonSet collecting pod logs → loki-gateway (sync-wave 7)
- [x] Grafana Loki datasource configured

### Vault Policy & Config
- [x] `vault/policies/platform-read.hcl` — read-only ACL for `secret/data/platform/*`
- [x] `vault/kubernetes-auth/role-backend-api.yaml` — k8s auth role
- [x] `vault/bootstrap/README.md`

---

## Phase 5 — CI/CD Layer (GitHub Actions)

- [x] `.github/workflows/ci.yaml` — Unified CI workflow with composite actions:
  - [x] `.github/actions/tools/` — Install terraform, kubectl, kind, trivy, yamllint
  - [x] `.github/actions/checks/` — terraform fmt/validate, yamllint, trivy config scan
  - [x] `.github/actions/terraform-kind/` — kind cluster + Argo CD bootstrap
  - [x] `.github/actions/terraform-eks/` — EKS stub (not implemented)
- [x] `.github/workflows/cleanup-local.yaml` — Manual KinD cluster cleanup
- [x] Composite action architecture — reusable steps
- [x] Cluster persists after apply (no auto-destroy)
- [x] Argo CD bootstrap verification step
- [x] `security.yml` — Trivy image scan on `apps/**` changes
- [ ] Add `workflow_dispatch` inputs to `ci.yaml`: `action: apply|destroy`, `environment: dev|staging`

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

- [~] App scaffolds exist (`apps/`, `gitops/workloads/layers/`)
- [ ] **backend-api**
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

- [x] Velero deployed via Argo CD (`gitops/platform-kind/layers/storage/velero.yaml`)
- [x] Backup storage: MinIO (`http://minio.minio.svc.cluster.local:9000`)
- [x] Velero pod running (sync-wave 4)
- [ ] `velero/schedules/` — BackupSchedule CRs (daily platform namespaces)
- [ ] `velero/restore/` — Restore procedure + tested runbook
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

## Known Issues

- `vault-secrets-webhook` HPA broken — missing `resources.requests.cpu` in container `secrets-webhook`
- Pod distribution imbalance — 25 pods on worker vs 8 on worker2, no nodeSelector/affinity


## Next Sprint Focus

```
1. [NEXT]  Fix vault-secrets-webhook HPA (add CPU request)
2. [NEXT]  Pod distribution affinity rules for heavy workloads
3. [PLAN]  Phase 7: Workload services (backend-api, worker, cronjob)
4. [PLAN]  Phase 8: Velero schedules + DR runbook
5. [PLAN]  Phase 6: RBAC policies + Network Policies
```
