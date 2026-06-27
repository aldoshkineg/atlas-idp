# Workloads — Implementation Roadmap

> **Legend:** `[ ]` Planned | `[x]` Done

**Project: Seal** — Document signing platform.
Accepts text input via web UI, queues processing jobs in Redis, asynchronously generates
signed PDFs and stores them in object storage (MinIO). User is notified on completion
and can download the signed document.

**Philosophy:** Application is a vehicle to demonstrate platform engineering.
15% Go code, 85% infrastructure (Helm, ArgoCD, Vault, KEDA, Observability, Security).

**Available in cluster:** CNPG 17.6, Redis, MinIO, KEDA, Vault (Bank-Vaults), Prometheus/Grafana/Loki/Alloy/Tempo, ArgoCD.

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

- [x] `go mod init`, Config with go-envconfig
- [x] `cmd/main.go` — startup, graceful shutdown, /healthz /readyz, background results consumer
- [x] `cmd/main.go` — `os.Args[1] == "migrate"` subcommand for standalone migration Job
- [x] `migrate.go` — `//go:embed migrations/*.sql`, run on `migrate` subcommand (NOT on startup)
- [x] `repository.go` — pgx: CreateDocument, GetDocument, UpdateStatus, pgxpool with `MaxConns=5`
- [x] `queue.go` — Redis: PushTask (RPUSH `seal:jobs`), PopResult (BLPOP `seal:results`)
- [x] `handler.go` — chi:
  - `POST /api/v1/documents` → repo.Create + queue.PushTask, return `{id}`
  - `GET /api/v1/documents/{id}` → repo.GetDocument, return JSON
  - `GET /api/v1/documents/{id}/download` → returns download URL
  - `GET /api/v1/documents/{id}/verify` → checks PG status, returns `{valid: true}` if `completed`
  - Logging middleware (slog, request_id, method, path, duration)
  - Metrics middleware (http_requests_total, http_request_duration_seconds)
  - Tracing middleware (OpenTelemetry — declared, span создаются, нет OTLP exporter)
  - CORS middleware
- [x] Dockerfile (multi-stage: `golang:1.26` → `scratch`, non-root, `-ldflags="-s -w"`)
- [x] **Test:** `go test ./...` — unit tests pass
- [x] **Test:** `go test -tags=integration ./...` — testcontainers: real postgres + redis, full POST/GET flow

---

## Phase 2 — Seal Worker (Go 1.26)

**Stack:** go-redis, minio-go, gofpdf, digitorus/pdfsign, slog, prometheus, otel.

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

- [x] Single chart `apps/seal/charts/seal/`:
  - `Chart.yaml`, `values.yaml` (zero secrets; `secrets.*` for dev overrides)
  - `templates/deployment-api.yaml` — Vault Agent annotations (conditional), envFrom ConfigMap/Secret, probes, resources
  - `templates/deployment-worker.yaml` — same + Vault Agent cert injection, redis-client label
  - `templates/deployment-ui.yaml` — same (minimal)
  - `templates/service.yaml` — seal-api:8080, seal-worker:9090, seal-ui:8081
  - `templates/servicemonitor.yaml` — Prometheus ServiceMonitor for API + Worker
  - `templates/vault-role.yaml` — RBAC roles for Vault Agent (conditional via `vault.enabled`)
  - `templates/migration-job.yaml` — ArgoCD PreSync hook, runs `./app migrate`
  - `templates/keda-scaledobject.yaml` — KEDA ScaledObject for worker (scale-to-zero)
  - `templates/cronjob.yaml` — DLQ reprocessor every 5min
  - `templates/configmap.yaml` — configmaps for all 3 components
  - `templates/secret.yaml` — values-driven via `.Values.secrets.*` (Vault in prod, --set in dev)
  - `templates/serviceaccount.yaml` — service accounts for all 3 components
  - `templates/httproute.yaml` — seal.atlas /api/ → seal-api, / → seal-ui
  - `templates/keda-trigger-auth.yaml` — Redis password auth for KEDA
- [x] **Test:** `helm lint apps/seal/charts/seal` — no errors
- [x] **Test:** `helm template apps/seal/charts/seal` — valid YAML output

---

## Phase 5 — GitOps (ArgoCD)

- [x] Single ArgoCD Application `atlasteam-seal` в `gitops/workloads/atlasteam/seal/app.yaml`
- [x] AppProject `workloads` — project для workloads
- [x] Gateway HTTPRoute `seal-route` для `seal.atlas` (/ → seal-ui, /api/ → seal-api)
- [x] KEDA ScaledObject for worker (scale-to-zero на длине очереди `seal:jobs`)
- [x] CiliumNetworkPolicy `seal` — deny-all default + allow rules
- [x] ResourceQuota `seal-quota` — CPU/Memory limits для atlasteam-seal
- [x] PodMonitor `seal` для Prometheus
- [x] PrometheusRule `seal-alerts`
- [x] CronJob `seal-dlq-reprocessor` каждые 5мин
- [x] ServiceAccounts: seal-api, seal-ui, seal-worker
- [x] Secrets: seal-api-secret, seal-worker-secret, seal-pdf-signer

---

## Phase 6 — Vault Integration

- [x] Vault operator + secrets webhook deployed (Bank-Vaults)
- [x] External Secrets Operator syncs platform secrets (MinIO, Redis, DB) в namespace
- [ ] Vault policy: `seal-workloads` — read `kv/data/seal/*`
- [ ] K8s auth role: `seal` — bound to SA in `atlasteam-seal` namespace

---

## Phase 8 — OpenTelemetry Instrumentation

- [x] **seal-api** (otel.Tracer уже есть, нет OTLP exporter)
  - [x] Add `go.opentelemetry.io/otel/exporters/otlp/otlptrace` dependency
  - [x] Init OTLP exporter + TracerProvider в `main.go` (читает `OTEL_EXPORTER_OTLP_ENDPOINT`)
  - [x] Настроить `pgx.QueryTracer` для трассировки SQL
  - [x] Настроить Redis hook для трассировки команд
  - [x] Propagate trace context в JSON `seal:jobs` (push) и `seal:results` (pop)
  - [x] Добавить span в `VerifyDocument` и background consumer (`PopResult`)
  - [x] Добавить span в chi middleware (все HTTP requests via otelhttp)
- [x] **seal-worker** (OTEL нет с нуля)
  - [x] Добавить `go.opentelemetry.io/otel` + OTLP exporter dependency
  - [x] Init OTLP exporter + TracerProvider в `main.go`
  - [x] Инструментировать `Worker.Run()` — span на lifecycle job
  - [x] Инструментировать `GeneratePDF` + `Sign` + MinIO `Upload` как дочерние спаны
  - [x] Propagate trace context извлечение из JSON `seal:jobs`, вложение в JSON `seal:results`
  - [x] Добавить Redis hook
- [x] **seal-ui** (OTEL нет с нуля)
  - [x] Добавить `go.opentelemetry.io/otel` + OTLP exporter dependency
  - [x] Init OTLP exporter + TracerProvider в `main.go`
  - [x] Инструментировать HTTP хендлеры
  - [x] Propagate trace context в HTTP headers к seal-api
- [ ] **Grafana** — настроить Tempo datasource
- [ ] **E2E проверка** — создать документ → проследить trace в Tempo (UI → API → Redis → Worker → MinIO → результат)
- [x] Docker Compose OTEL: `docker-compose.otel.yml` (Alloy + Tempo), `alloy.river`, `tempo.yaml`
- [x] Taskfile: `dc-up-otel`, `dc-down-otel`, `dc-logs-alloy`, `test-infra-otel`
- [x] `test-infra.sh` шаг 15 — проверка trace в Tempo API

---

## Phase 9 — Progressive Delivery (Argo Rollouts)

- [x] Argo Rollouts controller + dashboard deployed
- [x] **Rollout CR** — заменить seal-api Deployment на Rollout (blue-green/canary)
  - [x] Создать `templates/rollout-api.yaml` в Helm chart
  - [x] Настроить canary: 10% → 50% → 100% с анализом во время pause
  - [x] Traffic routing через Gateway API + Service weights (stable/canary)
  - [x] Prometheus health check для auto-promotion (seal-success-rate: error rate < 1%)
  - [x] Prometheus error budget check для auto-rollback (seal-latency: p95 < 500ms)
- [ ] **KEDA + Rollout** — проверить совместимость
- [ ] **KEDA + Rollout** — проверить совместимость
- [ ] E2E: git push → canary → validate → full rollout

---

## Phase 10 — Dashboards, Logging & SLOs — ✅ Done (2026-06-27)

- [x] Grafana dashboards:
  - Application: RPS, latency p50/p95/p99, error rate, queue depth
  - Worker: jobs/s, active pods, success rate, DLQ length
  - Business: documents created/failed, avg processing time
- [x] Structured JSON logs с `trace_id`/`span_id` → Alloy → Loki
- [x] PrometheusRules: `QueueBacklog`, `WorkerFailures`, `HighErrorRate`
- [x] SLO: API Latency 95% < 200ms
- [x] SLO: Worker Success Rate > 99%
- [x] Loki pipeline verified: `discovery.docker` → `loki.source.docker` → `loki.write`
- [x] Dashboard labels fixed: `container` (not `container_name`), `|= "error"` (not `level = `error``)
- [x] Loki config fixed: inmemory KV store (not consul) to avoid "Ingester is shutting down" loop
- [x] All 15/15 smoke tests pass with Loki + Prometheus + Tempo

---

## Phase 11 — Platform Hardening

- [ ] **Pod Security**: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL` в Helm templates
- [ ] **Cosign signing** образов в CI
- [ ] **k6 load tests** (`apps/tests/load/`)

---
