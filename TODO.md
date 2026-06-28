# Atlas IDP — Implementation Roadmap

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
  - [x] Zot cache registry support via containerd config patch (`enable_zot_cache = true`)
  - [x] Outputs: endpoint, ca_cert, client_cert, client_key, kubeconfig_path
- [x] `infra/environments/dev/main.tf` — active dev environment wires kind module
- [x] `infra/modules/argocd-bootstrap/` — complete Terraform module (Day-0 Helm install)
  - [x] `main.tf`: `helm_release "argocd"` with proper values (NodePort, repo creds)
  - [x] `variables.tf`: kube credentials, argocd_version, repo_url, namespace
  - [x] `versions.tf`: helm ~> 2.14, kubernetes ~> 2.33
- [x] Wire `module "argocd_bootstrap"` into `infra/environments/dev/main.tf`
- [x] Wire `null_resource "argocd_root_app"` into `infra/environments/dev/main.tf`

---

## Phase 2 — Kubernetes Runtime

- [x] Cluster creation via Terraform `kind_cluster` resource (tehcyx/kind provider)
- [x] Validate `kind` + `kubectl` installed on self-hosted runner
- [x] Install Cilium CNI (replace kindnet)

---

## Phase 3 — GitOps Layer (Argo CD)

> Day-0 and Day-1 bootstrap implemented. 20+ applications deployed and synced.

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
- [x] ArgoCD Project `workloads` — restricts workload apps (sync-wave -1), cluster-resources disabled
- [x] All child Application CRs migrated: `project: default` → `project: platform-kind`
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

- [x] **CloudNativePG** — Operator 1.29.1, cluster `production-db` (1 instance, PG 17.6, csi-hostpath-sc).
  - [x] Plugin-based recovery (no deprecated `externalClusters.barmanObjectStore`)
  - [x] `shared_buffers` reduced to 64MB (OOM risk fix)
  - [x] PodMonitor for Prometheus scrapes metrics (9187), verified `health=up`
  - [x] CNPG Grafana dashboard via `gnetId: 20417`
  - [x] Backup/restore test: 7/7 PASS (source → backup → recovery → verify 100 rows)
  - [x] Switch backup secrets to Vault (policies + external-secrets to sync k8s Secret)

### Base

- [x] **metrics-server** — deployed (sync-wave 1)

### Observability

- [x] **kube-prometheus-stack** — Prometheus + Grafana + Alertmanager (sync-wave 5)
  - [x] Custom alert rules: HighErrorRate, HPAMaxedOut — mounted as ConfigMap
  - [x] Grafana dashboards: platform overview (inline JSON), CNPG Cluster (gnetId 20417)
- [x] **loki** — SingleBinary mode, filesystem storage, 10d retention (sync-wave 6)
- [x] **alloy** — DaemonSet collecting pod logs → loki-gateway (sync-wave 7)
- [x] **tempo** — Distributed tracing backend (sync-wave 6)
- [x] Grafana Loki datasource configured
- [x] Grafana Tempo datasource configured (uid: tempo)

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
- [x] `.github/workflows/seal-docker-publish.yml` — build and push seal-api/seal-worker/seal-ui images

---

## Phase 6 — Security Baseline & Cluster Governance

- [x] `security/trivy/trivy.yaml` — Trivy config (HIGH/CRITICAL, IaC scan)
- [x] `security/rbac/` — RBAC policies
  - [x] `platform-admin` ClusterRole (full platform namespace access)
  - [x] `workload-deployer` Role (deploy-only to workload namespaces)
  - [x] `readonly` ClusterRole for observability service accounts
- [x] Network Policies — CiliumNetworkPolicy per namespace (deny-all default, allow ingress/monitoring)
- [x] CiliumClusterwideNetworkPolicy — ingress rules for platform and workload namespaces
- [x] Pod Security Standards — apply `restricted` profile via Pod Security Admission labels on namespaces
- [x] Trivy Operator deployed in-cluster (continuous runtime scanning)
- [x] ResourceQuota and LimitRange for workload namespaces
- [x] External Secrets Operator — syncs platform secrets from Vault to Kubernetes

---

## Phase 7 — Disaster Recovery (Velero)

- [x] Velero deployed via Argo CD (`gitops/platform-kind/layers/storage/velero.yaml`)
- [x] Backup storage: MinIO (`http://minio.minio.svc.cluster.local:9000`)
- [x] Velero pod running (sync-wave 4)
- [x] BackupSchedule CR (weekly PVC backups to S3 via fs-backup)

---

## Phase 8 — Progressive Delivery (Argo Rollouts)

- [x] Install Argo Rollouts controller + dashboard
- [x] **seal-api Rollout CR** — Deployment replaced with Rollout
  - [x] `templates/rollout-api.yaml` in Helm chart
  - [x] Canary strategy: 10% → pause 30s → 50% → pause 30s → 100%
  - [x] Traffic routing via Gateway API (managedRoutes + HTTPRoute `seal`)
  - [x] Tested with `v0.40` — full canary lifecycle verified
  - [x] Rollback tested with non-existent tag — manual rollback works
- [x] Prometheus analysis templates (`seal-success-rate`, `seal-latency`) — deployed and wired into Rollout canary steps
- [x] KEDA ScaledObject for `seal-worker` — deployed, Ready, Redis-triggered (min=1, max=20)
- [x] E2E: git push → ArgoCD sync → canary → validate → full rollout

---

## Phase 9 — Platform CLI & Developer Experience

- [x] **atlasctl** — bash-based workload management CLI (`tools/atlasctl/atlasctl.sh`)
  - [x] `new` — scaffold workload structure
  - [x] `seed` — provision DB + bucket + write secrets to Vault
  - [x] `enable` / `disable` — manage GitOps + Gateway listeners
  - [x] `status` / `list` — workload status
- [ ] **atlasctl** (Go CLI) — rewrite as standalone Go binary

  **Тестирование:** каждый пакет сопровождается unit-тестами (table-driven, минимум 70% coverage на пакет).
  Интеграционные тесты с реальными k8s/vault — опционально, в отдельном `_test.go` с build-тегом `//go:build integration`.
  Smoke-тест в конце Week 6 проходит полный lifecycle workload-а.

  - [ ] **Week 1 — Foundation**
    - [x] `pkg/config/` — YAML-driven config (template groups, defaults, seed keys, overlay via binary-side atlastctl.yaml)
    - [x] `tools/atlasctl/pkg/config/config.yaml` — default config with 4 template groups (14 files), 4 seed keys, 5 defaults
    - [x] Initialize Go module `tools/atlasctl/go.mod`, pin deps (cobra, gopkg.in/yaml.v3)
    - [ ] Cobra root command + `--version`, `--help`
    - [ ] Package structure: `cmd/`, `pkg/template/`, `pkg/seed/`, `pkg/gitops/`, `pkg/k8s/`, `pkg/vault/`, `pkg/gateway/`
    - [ ] `tools/atlasctl/Taskfile.yml` — targets: `build`, `test`, `test-integration`, `cover`, `vet`, `lint`, `clean`
    - [x] Define command scope: port `new`, `seed`, `enable`, `disable`, `delete`, `status`, `list` + add `logs`, `backup` trigger
    - [x] `tools/atlasctl/atlasctl.sh` — rename original, update all references (Makefile, README, TODO.md)
    - [x] `tools/atlasctl/README.md` — translate to English, add Go dev section, add architecture diagram
    - [x] `tools/atlasctl/.gitignore` — exclude `bin/`, `go.work`, `*.test`, `*.out`, `*.cov`, `coverage/`
    - [x] `tools/atlasctl/go.mod` — module `github.com/aldoshkineg/atlas-idp/tools/atlasctl`, dep cobra v1.10.2
    - [x] `tools/atlasctl/main.go` — entry point → `cmd.Execute()`
    - [x] `tools/atlasctl/cmd/root.go` — Cobra root with `--help`, `--version` (v0.1.0)
    - [x] `tools/atlasctl/cmd/{new,seed,enable,disable,delete,status,list,logs,backup}.go` — command stubs
    - [x] `tools/atlasctl/pkg/{template,seed,gitops,k8s,vault,gateway}/` — package stubs
    - [x] `tools/atlasctl/Taskfile.yml` — build, test, test-integration, cover, vet, lint, clean, tidy
    - [x] `tools/atlasctl/bin/atlasctl` — builds and runs, `--help` shows all 9 commands
    - [x] `AGENTS.md` — add atlasctl Go build/test instructions
    - [ ] **Тесты Week 1:** структура пакетов должна проходить `go vet`, скелет Cobra root — table-driven test на парсинг флагов
  - [ ] **Week 2 — Scaffold + Template Engine**
    - [x] `pkg/template/` — render templates/gold/ with `{{VAR}}` via `strings.ReplaceAll`
    - [x] `cmd/new.go` — port `cmd_new`: flags, validation, `.secret-seed` generation with `crypto/rand`
    - [x] `new` renders **all files from `templates/gold/`** recursively via `fs.WalkDir`, strips `.tmpl` suffix, preserves subdirectory structure — zero hardcoded file lists
    - [x] `config.yaml` — cleaned up: no hardcoded template groups, only scaffold directory, defaults, seed keys
  - [ ] **Week 3 — Seed (Infra Provisioning)**
    - [x] `pkg/k8s/` — kubectl-based wrapper: PodExec, SecretRead(Decoded), GetPodName, NamespaceExists
    - [x] `pkg/vault/` — Vault client via vault-0 pod exec: KVPut, KVGet (stub), root token read
    - [x] `pkg/seed/` — CNPG DB/user creation (psql exec), MinIO bucket/user (mc exec), Vault write
    - [x] `cmd/seed.go` — port cmd_seed fully: --dry-run, --force, -y, validation, confirm prompt
    - [x] **Тесты Week 3:** `pkg/seed/` — table-driven LoadParams + ValidateParams (with extra secrets); `pkg/k8s/` + `pkg/vault/` — constructor tests + integration build-tag stubs; `cmd/seed.go` — cobra flag tests (no-arg, invalid-format, dry-run)
  - [ ] **Week 4 — GitOps Management**
    - [x] `pkg/gateway/` — Gateway API listener CRUD (LoadGateway/SaveGateway, AddListener, RemoveListener, HasListener), YAML round-trip via `sigs.k8s.io/yaml`
    - [x] `pkg/gitops/` — file ops: CopyWorkloadManifest, SyncResources (excludes app.yaml, gateway.yaml, .secret-seed, vault, \*.tmpl), RemoveAll, RemoveEmptyDir, ApplyGatewayListener (add/remove)
    - [x] `cmd/enable.go` — port from bash: --dry-run, --sync, --push, --force, -y, copy app.yaml, rsync resources, copy gateway route, add listener, git commit/push
    - [x] `cmd/disable.go` — port from bash: --dry-run, --sync, --push, -y, remove listener, delete gitops files, clean empty dirs, git commit/push
    - [x] `cmd/delete.go` — port from bash: --dry-run, -y, refuses if enabled, removes workload dir + empty group dir
    - [x] **Тесты Week 4:** `pkg/gateway/` — add/remove/has listener, load/save round-trip, file-not-found; `pkg/gitops/` — SyncResources exclusions, CopyWorkloadManifest creates subdirs, RemoveEmptyDir, ApplyGatewayListener add/remove/duplicate; `cmd/` — flag validation (no-arg, invalid-format), workload-not-found, dry-run, still-enabled checks
  - [x] **Week 5 — Read Commands + ArgoCD API**
    - [x] `cmd/status.go`, `cmd/list.go` — port from bash
    - [x] `pkg/argocd/` — ArgoCD API client: `ApplicationService.Get`, sync status, rollout promotion
    - [x] `cmd/logs.go` — `kubectl logs --tail=` via k8s API
    - [x] `cmd/backup.go` — trigger CNPG backup (Backup CR)
    - [x] **Тесты Week 5:** `pkg/argocd/` — unit tests; `cmd/` — flag validation, dry-run, JSON/plain, detect_features
  - [x] **Week 6 — Integration, CI, README**
    - [x] Update `root Taskfile.yml` — alias `atlasctl:build`, `atlasctl:test` via `task: tools/atlasctl`
    - [x] Update CI — build + test Go binary in ci.yaml
    - [x] Update `Makefile` — atlasctl targets → Go binary
    - [x] Smoke test: full `new → seed → enable → status → disable → delete` cycle via Go binary (`cmd/smoke_test.go`, `//go:build integration`)
  - [x] **Phase 9 — atlasctl Go CLI — COMPLETE**

- [ ] **Final Showcase Presentation**
  - [ ] Script and record end-to-end demo (GitOps push → Canary → KEDA scale → Trace → DR)

---

## Phase 10 — Supply Chain Security & Admission Control

- [ ] **Cosign** — container image signing in CI
  - [ ] `cosign generate-key-pair` → private key in GitHub Secrets, public key in repo
  - [ ] Add `cosign sign --key` to `.github/workflows/seal-docker-publish.yml` after push
  - [ ] Keyless verification for third-party images (Grafana, Loki, etc.)
- [ ] **Kyverno / Policy Controller** — Admission Control
  - [ ] Deploy Kyverno via Argo CD (sync-wave 1)
  - [ ] **Validate: `disallow latest tag`** — block `:latest` image deployments
  - [ ] **Validate: `require-run-as-non-root`** — all pods must set `runAsNonRoot: true`
  - [ ] **Mutate: auto-add security context** — inject `readOnlyRootFilesystem`, `drop: ALL`, `seccomp: RuntimeDefault`
  - [ ] **Validate: `require-labels`** — enforce `app.kubernetes.io/name`, `app.kubernetes.io/instance`
  - [ ] **Validate: `disallow-privileged`** — block `privileged: true` and `hostPath` in workload namespaces
  - [ ] **Validate: `require-image-signature`** — block unsigned images for `ghcr.io/aldoshkineg/*`
  - [ ] **Mutate: auto-add Alloy sidecar** — optionally inject log collector into all pods in `atlasteam-seal`

---

## Phase 11 — Documentation & ADRs

- [ ] **Architecture Decision Records (ADRs)** — `docs/adr/`
  - [ ] ADR-001: Workload onboarding pattern (atlasctl → GitOps → Vault → Gateway)
  - [ ] ADR-002: Secrets strategy (ExternalSecrets vs Vault Agent)
  - [ ] ADR-003: Rollout vs Deployment decision
  - [ ] ADR-004: Observability stack choices (Prom/Loki/Tempo/Alloy)
- [ ] **Platform overview** — `docs/` with architecture diagram, component relationships
- [ ] **Runbooks** — `docs/runbooks/`
  - [ ] Cluster recovery from Velero backup
  - [ ] Canary abort / promote procedures
  - [ ] Vault unseal procedure
- [ ] **Disaster Recovery drill** — document and verify Velero restore end-to-end

---
