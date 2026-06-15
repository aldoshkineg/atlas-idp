# Workloads — Implementation Roadmap

> **Legend:** `[ ]` Planned | `[x]` Done

**Project: Seal** — Document signing platform.
Accepts text input via web UI, queues processing jobs in Redis, asynchronously generates
signed PDFs and stores them in object storage (MinIO). User is notified on completion
and can download the signed document.

**Philosophy:** Application is a vehicle to demonstrate platform engineering.
15% Go code, 85% infrastructure (Helm, ArgoCD, Vault, KEDA, Observability, Security).

**Available in cluster:** CNPG 17.6, Redis, MinIO, KEDA, Vault (Bank-Vaults), Prometheus/Grafana/Loki/Alloy, ArgoCD.

---

## Phase 0 — Docker Compose

**Goal:** Local dev without Kubernetes.

- [x] `docker-compose.yml` — postgres:17-alpine, redis:7-alpine, minio/minio (in `apps/tests/integration/`)
- [x] `.env.example` — all required and optional vars for seal-api, seal-worker, seal-ui
- [x] `Taskfile.yml` targets: `dc-up`, `dc-down`, `run-api`, `run-worker`, `gen-certs`
- [x] **Test:** `apps/tests/integration/test-infra.sh` — 14 smoke tests (all pass)

---

## Phase 1 — Seal API (Go 1.26)

**Stack:** chi, pgx, go-redis, go-envconfig, slog, prometheus, otel.

```
apps/seal-api/
├── cmd/
│   └── api/
│       ├── main.go
│       └── main_test.go
├── internal/
│   ├── config.go
│   ├── config_test.go
│   ├── handler.go
│   ├── handler_test.go
│   ├── handler_integration_test.go
│   ├── repository.go
│   ├── repository_test.go
│   ├── queue.go
│   ├── queue_test.go
│   ├── migrate.go
│   ├── migrate_test.go
│   └── migrations/
│       └── 001_create_documents.sql
├── Dockerfile
└── go.mod
```

- [x] `go mod init`, Config with go-envconfig
- [x] `cmd/main.go` — startup, graceful shutdown, /healthz /readyz, background results consumer
- [x] `cmd/main.go` — `os.Args[1] == "migrate"` subcommand for standalone migration Job
- [x] `migrate.go` — `//go:embed migrations/*.sql`, run on `migrate` subcommand (NOT on startup)
- [x] `repository.go` — pgx: CreateDocument, GetDocument, UpdateStatus, pgxpool with `MaxConns=5`
- [x] `queue.go` — Redis: PushTask (RPUSH `seal:jobs`), PopResult (BLPOP `seal:results`)
- [x] `handler.go` — chi:
  - `POST /api/v1/documents` → repo.Create + queue.PushTask, return `{id}`
  - `GET /api/v1/documents/{id}` → repo.GetDocument, return JSON
  - `GET /api/v1/documents/{id}/download` → returns download URL (constructed from config prefix, no MinIO client)
  - `GET /api/v1/documents/{id}/verify` → checks PG status, returns `{valid: true}` if `completed`
  - Logging middleware (slog, request_id, method, path, duration)
  - Metrics middleware (http_requests_total, http_request_duration_seconds)
  - Tracing middleware (OpenTelemetry)
  - CORS middleware
- [x] Dockerfile (multi-stage: `golang:1.26` → `scratch`, non-root, `-ldflags="-s -w"`, `--mount=type=cache` for go mod + build cache)
- [x] **Test:** `go test ./...` — unit tests pass
- [x] **Test:** `go test -tags=integration ./...` — testcontainers: real postgres + redis, full POST/GET flow

---

## Phase 2 — Seal Worker (Go 1.26)

**Stack:** go-redis, minio-go, gofpdf, digitorus/pdfsign, slog, prometheus, otel.

```
apps/seal-worker/
├── cmd/
│   └── worker/
│       ├── main.go
│       └── main_test.go
├── internal/
│   ├── config.go
│   ├── config_test.go
│   ├── worker.go           # BLMove loop + retry/DLQ + results queue push
│   ├── worker_test.go
│   ├── worker_integration_test.go
│   ├── pdf.go              # gofpdf: text → PDF
│   ├── pdf_test.go
│   ├── signer.go           # PDF cryptographic signing (digitorus/pdfsign)
│   ├── signer_test.go      # sign + verify round-trip + tamper + untrusted CA
│   ├── storage.go          # minio-go: Upload to seal-outputs/{id}.pdf
│   └── storage_test.go
├── Dockerfile
└── go.mod
```

- [x] `go mod init`
- [x] Config struct (CryptoConfig with Vault-default paths)
- [x] `cmd/main.go` — graceful shutdown, finish in-flight job
- [x] `pdf.go` — gofpdf: text → PDF (A4, monospace, plain layout)
- [x] `signer.go` — PDF cryptographic signing with `digitorus/pdfsign`
- [x] `worker.go` — main loop with BLMOVE, retry, DLQ
- [x] Retry logic: 3 attempts via `LLen` on processing queue, then push to `seal:dlq`
- [x] **Exponential backoff** on MinIO upload: retry 3 times with 1s/2s/4s delay
- [x] Metrics: pdf_sign_duration_seconds, pdf_sign_errors_total, jobs_processed_total, job_duration_seconds
- [x] Dockerfile (multi-stage: golang → `scratch`, cache mounts, `-ldflags="-s -w"`)
- [x] **Test:** `go test ./...` — unit tests pass
- [x] **Test:** `go test -tags=integration ./...` — testcontainers: real redis + minio, full job lifecycle

---

## Phase 3 — Seal UI (Go + HTMX)

**Stack:** Go 1.26, chi, html/template, HTMX, Tailwind CSS (CDN).

```
apps/seal-ui/
├── cmd/
│   └── ui/
│       └── main.go
├── internal/
│   ├── config.go
│   ├── server.go
│   ├── handlers/
│   │   ├── page.go              # GET / — main form
│   │   └── document.go          # POST /documents, GET /documents/{id}/status (HTMX)
│   ├── templates/
│   │   ├── base.html            # layout
│   │   ├── index.html           # textarea + Submit
│   │   ├── status.html          # spinner → hx-get polling
│   │   ├── status_pending.html  # continue polling
│   │   └── download.html        # download link + verify
│   └── client/
│       └── api.go               # HTTP client to seal-api
├── Dockerfile
├── go.mod
├── .env.example                 # BACKEND_API_URL=http://localhost:8080
```

- [x] `go mod init`, Config (`BACKEND_API_URL`, `PORT`)
- [x] `cmd/main.go` — chi router, graceful shutdown, /healthz /readyz
- [x] `internal/client/api.go` — CreateDocument, GetDocument, GetDownloadURL, VerifyDocument
- [x] Templates: base.html, index.html, status.html, status_pending.html, download.html
- [x] Handlers: page (GET /), document (POST /documents, GET /documents/{id}/status, download)
- [x] Dockerfile — multi-stage (golang:1.26 → chainguard/static, non-root)
- [x] Metrics: http_requests_total, http_request_duration_seconds, frontend_backend_requests_total
- [x] **Test:** `go test ./...` — unit tests with mock client
- [x] **Test:** `go vet ./...` — no errors

---

## Phase 4 — Helm Chart

- [x] Single chart `apps/charts/seal/`:
  - `Chart.yaml`, `values.yaml` (zero secrets — host/port/logLevel only; `secrets.*` for dev overrides)
  - `templates/deployment-api.yaml` — Vault Agent annotations (conditional via `vault.enabled`), envFrom ConfigMap/Secret, probes, resources, direct entrypoint (no shell)
  - `templates/deployment-worker.yaml` — same + Vault Agent cert injection, redis-client label
  - `templates/deployment-ui.yaml` — same (minimal)
  - `templates/service.yaml` — seal-api:8080, seal-worker:9090, seal-ui:8081
  - `templates/servicemonitor.yaml` — Prometheus ServiceMonitor for API + Worker
  - `templates/vault-role.yaml` — RBAC roles for Vault Agent
  - `templates/migration-job.yaml` — ArgoCD PreSync hook, runs `./app migrate`
  - `templates/keda-scaledobject.yaml` — KEDA ScaledObject for worker (scale-to-zero)
  - `templates/cronjob.yaml` — DLQ reprocessor every 5min
  - `templates/configmap.yaml` — configmaps for all 3 components
  - `templates/secret.yaml` — values-driven via `.Values.secrets.*` (Vault in prod, --set in dev)
  - `templates/serviceaccount.yaml` — service accounts for all 3 components
  - `templates/httproute.yaml` — seal.atlas / → seal-ui, /api/ → seal-api
- [x] **Test:** `helm lint apps/charts/seal` — no errors
- [x] **Test:** `helm template apps/charts/seal` — valid YAML output

---

## Phase 5 — GitOps (ArgoCD)

- [x] Single ArgoCD Application `seal` in `gitops/workloads/layers/seal/seal.yaml`
- [x] AppProject `seal` in `gitops/workloads/layers/seal/project.yaml`
- [x] Gateway API HTTPRoutes:
  - `seal.atlas` `/` → seal-ui:8081
  - `seal.atlas` `/api/` → seal-api:8080
- [x] KEDA ScaledObject for worker (scale-to-zero on `seal:jobs` queue length)
- [x] **Test:** `yamllint gitops/workloads/layers/` — valid YAML
- [ ] **Test:** `argocd app sync root-app` — apps create and sync successfully
     ⚠️ Sync temporarily disabled (root-app: no automated, seal: deleted from cluster)

---

## Phase 6 — Vault Integration

- [ ] Vault policy: `seal-workloads` — read `kv/data/seal/*`
- [ ] K8s auth role: `seal` — bound to SA in `seal` namespace
- [ ] Secrets in Vault: `kv/data/seal/seal-api`, `kv/data/seal/seal-worker`, `kv/data/seal/seal-ui`
- [ ] PDF signing cert in Vault: `kv/data/seal/pdf-signer`
- [ ] Vault Agent injection annotations in Helm deployment templates
- [ ] Bootstrap script: `security/vault-bootstrap-seal.sh`
- [ ] **Test:** `vault policy read seal-workloads` — policy exists
- [ ] **Test:** Deploy pod with Vault annotations → verify `/vault/secrets/config` exists

---

## Phase 7 — MinIO Buckets

- [x] Create `seal-outputs` bucket with `policy: download` (in MinIO chart via `gitops/platform-kind/layers/storage/minio.yaml`)
- [ ] Lifecycle policy (30-day retention)
- [ ] **Test:** `mc ls myminio/seal-outputs` — bucket exists
- [ ] **Test:** Upload + lifecycle policy — verify 30-day rule applied

---

## Phase 8 — Observability

- [ ] Grafana dashboards:
  - Application: RPS, latency p50/p95/p99, error rate, queue depth
  - Worker: jobs/s, active pods, success rate, DLQ length
  - Business: documents created/failed, avg processing time
- [ ] Loki: structured log correlation by `request_id`
- [ ] PrometheusRules: `QueueBacklog`, `WorkerFailures`, `HighErrorRate`
- [ ] **Test:** Grafana API — dashboards provisioned and visible
- [ ] **Test:** Prometheus — targets are up (seal-api, seal-worker, redis, cnpg)

---

## Phase 9 — Platform Hardening

- [ ] **PgBouncer**: enable CNPG connection pooler — `pooler.mode: transaction`, 2 instances
- [ ] NetworkPolicies:
  ```
  seal-ui → seal-api
  seal-api → postgres (5432)
  seal-api → redis (6379)
  seal-worker → redis (6379)
  seal-worker → minio (9000)
  deny-all else
  ```
- [ ] Pod Security: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`
- [ ] Cosign signing in CI
- [ ] Velero backup schedules for workload namespaces
- [ ] **Test:** `kubectl exec` cross-namespace — blocked by NetworkPolicy
- [ ] **Test:** Velero backup created successfully
- [ ] **Test:** Trivy scan — zero HIGH/CRITICAL in chainguard images

---

## Phase 10 — CI/CD

**Goal:** Modern container build pipeline — BuildKit, GHA cache, Trivy, Cosign, GHCR.

- [ ] Local build via Taskfile:
  ```yaml
  build-api:
    cmds:
      - docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/atlas-idp/seal-api:dev apps/seal-api
  ```
- [ ] GitHub Actions pipeline with test → build → trivy → cosign → push
- [ ] Image tagging: `sha-{short}`, `v{semver}`, never `latest`
- [ ] Trivy image scan (HIGH/CRITICAL fail)
- [ ] Cosign signing
- [ ] SBOM generation (syft or trivy)
- [ ] k6 load tests (`apps/tests/load/`)
- [ ] DR runbook: backup → delete → restore → verify
- [ ] **Test:** GHA workflow runs green on PR
- [ ] **Test:** `cosign verify` passes on pushed image

---

## Time Allocation

| Area                                | %   |
| ----------------------------------- | --- |
| Go code (API + Worker)              | 10% |
| PDF signing (signer.go, verify)     |  5% |
| Frontend (Go + HTMX)                | 10% |
| Helm chart                          | 15% |
| ArgoCD manifests + GitOps           | 20% |
| Vault policies + injection          | 15% |
| Monitoring/Logging/Tracing          | 15% |
| KEDA ScaledObject                   |  5% |
| NetworkPolicies + Velero + Security |  5% |