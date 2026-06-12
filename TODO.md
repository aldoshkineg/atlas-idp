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
- [x] Install Cilium CNI (replace kindnet)

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
  - [x] **HPA fixed**: added `resources.requests.cpu: 100m` + autoscaling config

### Storage
- [x] **snapshot-crds** — VolumeSnapshot CRDs (sync-wave 1)
- [x] **snapshot-controller** — CSI Snapshot controller (sync-wave 2)
- [x] **csi-hostpath** — CSI driver for local persistent volumes (sync-wave 3)
- [x] **minio** — S3-compatible object storage (sync-wave 3)
- [x] **velero** — backup/restore, backed by MinIO (sync-wave 4)

### Data
- [x] **postgresql** — PostgreSQL 16 (Bitnami), Velero pre-hook pg_dump, probes, postgres-exporter + ServiceMonitor (sync-wave 7)

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
- [x] `clusters/kind/ci/act-runner/Dockerfile` + `.actrc` + Makefile targets for local CI execution via act
- [ ] Add `workflow_dispatch` inputs to `ci.yaml`: `action: apply|destroy`, `environment: dev|staging`

---

## Phase 6 — Security Baseline & Cluster Governance

- [x] `security/trivy/trivy.yaml` — Trivy config (HIGH/CRITICAL, IaC scan)
- [x] `security/rbac/` — RBAC policies
  - [x] `platform-admin` ClusterRole (full platform namespace access)
  - [x] `workload-deployer` Role (deploy-only to workload namespaces)
  - [x] `readonly` ClusterRole for observability service accounts
- [x] `topologySpreadConstraints` applied to prometheus, grafana, alertmanager, loki
- [ ] Network Policies — namespace isolation (deny-all default, allow ingress/monitoring to workloads)
- [ ] Pod Security Standards — `restricted` profile and `readOnlyRootFilesystem` configurations
- [ ] Trivy Operator deployed in-cluster (continuous runtime scanning)
- [ ] Enforce namespace standards — `ResourceQuota` and `LimitRange` rules for workloads pool

---

## Phase 7 — Workloads Layer (text2pdf Platform)

- [~] App scaffolds exist (`apps/`, `gitops/workloads/layers/`)
- [ ] **Shared Stateful Backends**
  - [x] **PostgreSQL 16 (Bitnami):** Deployed via ArgoCD (sync-wave 7). PVC 8Gi, probes, postgres-exporter + ServiceMonitor, Velero pre-hook pg_dump. Vault secret injection pending.
  - [ ] **Redis (Bitnami):** Enable AOF persistence for queue stability and deploy `redis-exporter`
  - [ ] **MinIO:** Create S3 buckets (`text2pdf-inputs`/`outputs`) and setup a 7-day auto-purge lifecycle policy
- [ ] **backend-api (Go 1.24)**
  - [ ] Multi-stage non-root Dockerfile, Helm chart, Deployment, Service, HPA, PDB
  - [ ] REST endpoints (accept `.txt`, upload to MinIO, write metadata to PG, push task ID to Redis)
  - [ ] Liveness / Readiness / Startup probes, custom `/metrics` and `/healthz` endpoints
- [ ] **worker (Go 1.24)**
  - [ ] Queue consumer loop (`BLPOP`), PDF generation (`gofpdf`), state updates in Postgres
  - [ ] Implement robust Graceful Shutdown to prevent raw process termination during generation
  - [ ] Apply `topologySpreadConstraints` and expose `/metrics` endpoint
- [ ] **frontend (React 19 / Vite 7 / Nginx)**
  - [ ] Upload interface, polling status checks, and PDF viewing pane
  - [ ] Route traffic using Gateway API `HTTPRoute` resources (bind frontend to `/`, API to `/api`)
- [ ] **Autoscaling (KEDA)**
  - [ ] Deploy KEDA `ScaledObject` pointing to the worker deployment triggered by Redis queue length
  - [ ] Configure **scale-to-zero** (shrink worker pool to 0 replicas when idle) and test scaling thresholds
- [ ] **GitOps Delivery Pipeline**
  - [ ] GHA workflows to build all three images, run `helm lint` validation, scan via Trivy, and push to Zot
  - [ ] Implement automatic image tag updates in the GitOps repo triggering automated ArgoCD sync

---

## Phase 8 — Disaster Recovery (Velero)

- [x] Velero deployed via Argo CD (`gitops/platform-kind/layers/storage/velero.yaml`)
- [x] Backup storage: MinIO (`http://minio.minio.svc.cluster.local:9000`)
- [x] Velero pod running (sync-wave 4)
- [ ] `velero/schedules/` — BackupSchedule CRs (daily platform and workloads namespaces + volume snapshots)
- [ ] `velero/restore/` — Restore procedure + tested runbook
- [ ] DR runbook: `docs/runbooks/disaster-recovery.md`
  - [ ] Document precise RTO/RPO metrics
  - [ ] **Live Validation Drill:** Upload data → take Velero backup → destroy cluster via `kind delete cluster` → bootstrap fresh environment with Terraform → execute Velero restore → verify total application state and file recoverability

---

## Phase 9 — Advanced Application Observability & Tracing

- [ ] **Distributed Tracing Stack**
  - [ ] Deploy **Grafana Tempo** inside the cluster via ArgoCD
  - [ ] Instrument Go 1.24 applications with **OpenTelemetry SDK**
  - [ ] Trace the request lifecycle end-to-end: Frontend UI → Backend API → Redis Queue serialization → Worker execution
- [ ] **Dashboards & Logging**
  - [ ] Refactor app logs to structured JSON and inject correlation variables (`task_id`) into Alloy -> Loki
  - [ ] Build custom Grafana dashboards: App Performance (latency, error rates) and Queue Processing (KEDA replicas vs backlog)
- [ ] **SLOs & Advanced Alerting**
  - [ ] Define API Latency SLO (95% < 200ms) and Worker Success Rate SLO
  - [ ] Configure critical alert rules in Prometheus: `QueueBacklog` (KEDA at max but backlog growing), `WorkerFailures`, `PostgreSQLUnavailable`

---

## Phase 10 — Progressive Delivery & Service Mesh

- [ ] **Service Mesh (Linkerd)**
  - [ ] Deploy Linkerd and inject sidecar proxies across the `workloads` namespace
  - [ ] Verify zero-config mutual TLS (mTLS) for all internal communication and visualize service topologies
- [ ] **Progressive Delivery (Argo Rollouts)**
  - [ ] Install Argo Rollouts controller and refactor the `backend-api` deployment into a `Rollout` CRD
  - [ ] Configure a Canary deployment strategy (route 10% traffic to new version, validate via Prometheus metrics, auto-rollback on error spikes)
- [ ] **Final Showcase Presentation**
  - [ ] Script and record a final end-to-end platform showcase demo (GitOps push → Canary check → KEDA auto-scale 0 to max under load → Grafana trace navigation → Cluster destruction and Velero recovery)

---

## Phase 11 — Developer Experience, Golden Paths & AWS Readiness

- [ ] **Developer Tooling & Golden Path**
  - [ ] Create standardized Go app service and Helm chart templates
  - [ ] Write a developer onboarding guide and workload onboarding documentation
- [ ] **Architecture & Documentation**
  - [ ] `docs/architecture.md` — layered system overview + decision log
  - [ ] `docs/diagrams/` — draw.io / Mermaid architecture diagrams
    - [ ] Platform overview (layers)
    - [ ] GitOps flow (git push → Argo CD sync → k8s)
    - [ ] Secrets flow (Vault → workload)
  - [ ] `docs/runbooks/argocd-bootstrap.md`
  - [ ] `docs/runbooks/vault-init.md`
  - [ ] `docs/runbooks/disaster-recovery.md`
- [ ] **Architecture Decisions Logs**
  - [ ] Create `docs/adr/ADR-001-gitops-strategy.md`
  - [ ] Create `docs/adr/ADR-002-vault-integration.md`
  - [ ] Create `docs/adr/ADR-003-keda-adoption.md`
  - [ ] Create `docs/adr/ADR-004-object-storage-design.md`
- [ ] **AWS / EKS Readiness Plan**
  - [ ] EKS module (`infra/modules/eks/`) and IRSA roles module (`infra/modules/iam/`)
  - [ ] S3 Terraform remote state backend
  - [ ] Document the local-kind to AWS migration path (maintaining identical GitOps layers)

---

## Known Issues

- [x] `vault-secrets-webhook` HPA broken — Fixed: added missing `resources.requests.cpu` in container
- [x] Pod distribution — Fixed: added topologySpreadConstraints to prometheus, grafana, alertmanager, loki
- [x] `vault-secrets-webhook` MWC CA bundle drift — Fixed: restored ignoreDifferences

## Cluster Health

- 3 nodes, all Ready
- 20 ArgoCD apps, all Synced/Healthy
- ⚠️ Orphaned `VolumeSnapshotContent` objects (~10) after snapshot cleanup — no functional impact but noisy `SnapshotDeleteError` events

## Next Sprint Focus

```
1. Phase 6 — Network Policies: deny-all default per namespace, allow ingress + monitoring
2. Phase 6 — ResourceQuota + LimitRange for workloads pool
3. Phase 7 — Stateful Services: Redis (Bitnami charts via ArgoCD) + MinIO buckets
4. Phase 7 — Deploy KEDA ScaledObject for worker autoscaling (KEDA already installed)
5. Phase 4/Data — Vault secret injection for PostgreSQL
```
