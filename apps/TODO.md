# Workloads — Implementation Roadmap

> **Legend:** `[ ]` Planned

**Philosophy:** Application is a vehicle to demonstrate platform engineering.
15% Go code, 85% infrastructure (Helm, ArgoCD, Vault, KEDA, Observability, Security).

**Available in cluster:** CNPG 17.6, Redis, MinIO, KEDA, Vault (Bank-Vaults), Prometheus/Grafana/Loki/Alloy, ArgoCD.

---

## Phase 0 — Docker Compose

**Goal:** Local dev without Kubernetes.

- [x] `docker-compose.yml` — postgres:17-alpine, redis:7-alpine, minio/minio (in `apps/tests/integration/`)
- [x] `.env.example` — all required and optional vars for both backend-api and worker
- [x] `Taskfile.yml` targets: `dc-up`, `dc-down`, `run-api`, `run-worker`, `gen-certs`
- [x] **Test:** `apps/tests/integration/test-infra.sh` — 14 smoke tests (all pass)

---

## Phase 1 — Backend API (Go 1.25)

**Stack:** chi, pgx, go-redis, go-envconfig, slog, prometheus, otel.

**Flat structure — no service layer, no telemetry package:**
```
apps/backend-api/
├── cmd/
│   ├── main.go
│   └── main_test.go
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
- [x] `queue.go` — Redis: PushTask (RPUSH `text2pdf:jobs`), PopResult (BLPOP `text2pdf:results`)
- [x] `handler.go` — chi:
  - `POST /api/v1/documents` → repo.Create + queue.PushTask, return `{id}`
  - `GET /api/v1/documents/{id}` → repo.GetDocument, return JSON
  - `GET /api/v1/documents/{id}/download` → returns download URL (constructed from config prefix, no MinIO client)
  - `GET /api/v1/documents/{id}/verify` → checks PG status, returns `{valid: true}` if `completed`
  - Logging middleware (slog, request_id, method, path, duration)
  - Metrics middleware (http_requests_total, http_request_duration_seconds)
  - Tracing middleware (OpenTelemetry)
  - CORS middleware
- [x] Dockerfile (multi-stage: `golang:1.25` → `scratch`, non-root, `-ldflags="-s -w"`, `--mount=type=cache` for go mod + build cache)
- [x] **Test:** `go test ./...` — unit tests pass
- [x] **Test:** `go test -tags=integration ./...` — testcontainers: real postgres + redis, full POST/GET flow

---

## Phase 2 — Worker (Go 1.25)

**Stack:** go-redis, minio-go, gofpdf, digitorus/pdfsign, slog, prometheus, otel.

```
apps/worker/
├── cmd/
│   ├── main.go
│   └── main_test.go
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
│   ├── storage.go          # minio-go: Upload to text2pdf-outputs/{id}.pdf
│   └── storage_test.go
├── Dockerfile
└── go.mod
```

- [x] `go mod init`
- [x] Config struct (CryptoConfig with Vault-default paths)
- [x] `cmd/main.go` — graceful shutdown, finish in-flight job
- [x] `pdf.go` — gofpdf: text → PDF (A4, monospace, plain layout)
- [x] `signer.go` — PDF cryptographic signing with `digitorus/pdfsign`:
  ```go
  func (s *Signer) Sign(ctx context.Context, pdfData []byte) ([]byte, error)
  ```
  - Loads X.509 cert + key from PEM files at startup (reads from file paths)
  - Uses `crypto.Signer` interface (not just `*rsa.PrivateKey`)
  - Uses `sign.Sign()` / `verify.VerifyWithOptions()` from `digitorus/pdfsign` v0.0.0-20260407063256
  - Configurable cert/key via `SIGN_CERT_PATH` / `SIGN_KEY_PATH` env vars
  - **Dev:** reads from `apps/.certs/` (gitignored, generated via `go-task gen-certs`)
  - **Prod:** Vault Agent injects into `/vault/secrets/tls.{crt,key}`
  - Signature info: `Atlas IDP`, reason `Document authenticity`
- [x] `worker.go` — main loop:
  ```
  job := redis.BLMove(text2pdf:jobs → text2pdf:processing)
  rawPDF := pdf.Generate(job.InputText)
  signedPDF := signer.Sign(rawPDF)
  storage.Upload(job.DocumentID, signedPDF)
  redis.LPush(text2pdf:results, {document_id, status, s3_path})
  redis.LRem(text2pdf:processing)
  ```
  - Job message is JSON `{document_id, input_text}` (no PostgreSQL)
  - Writes results to `text2pdf:results` Redis list
  - Per-step logging (pdf generated, signed, uploaded, result pushed, job completed)
- [x] Retry logic: 3 attempts via `LLen` on processing queue, then push to `text2pdf:dlq`
- [x] **Exponential backoff** on MinIO upload: retry 3 times with 1s/2s/4s delay
- [x] Metrics:
  - `pdf_sign_duration_seconds` (histogram)
  - `pdf_sign_errors_total` (counter)
  - `pdf_verify_total` (counter)
  - `jobs_processed_total{status="ok|fail"}` (counter)
  - `job_duration_seconds` (histogram)
- [x] Dockerfile (multi-stage: golang → `scratch`, cache mounts, `-ldflags="-s -w"`)
- [x] **Test:** `go test ./...` — unit tests pass
- [x] **Test:** `go test -tags=integration ./...` — testcontainers: real redis + minio, full job lifecycle

---

## Phase 3 — Helm Charts

- [ ] `apps/charts/backend-api/`:
  - `Chart.yaml`, `values.yaml` (zero secrets — host/port/logLevel only)
  - `templates/deployment.yaml` — Vault Agent annotations, envFrom ConfigMap, probes, resources
  - `templates/service.yaml`
  - `templates/servicemonitor.yaml`
  - `templates/vault-role.yaml`
  - `templates/migration-job.yaml` — ArgoCD PreSync hook, runs `./app migrate`, deletes on success
- [ ] `apps/charts/worker/` — same structure
- [ ] `apps/charts/frontend/` — same (minimal)
- [ ] **Test:** `helm lint apps/charts/*` — no errors
- [ ] **Test:** `helm template apps/charts/backend-api` — valid YAML output

---

## Phase 4 — GitOps (ArgoCD)

- [ ] ArgoCD Application manifests in `gitops/workloads/layers/`:
  - `backend-api.yaml`, `worker.yaml`, `frontend.yaml`
- [ ] Gateway API HTTPRoutes:
  - `api.text2pdf.local` → backend-api:8080
  - `app.text2pdf.local` → frontend:80
- [ ] KEDA ScaledObject for worker:
  ```yaml
  minReplicaCount: 0
  maxReplicaCount: 20
  triggers:
    - type: redis-list
      metadata:
        address: redis.redis:6379
        listName: text2pdf:jobs
        listLength: "1"
  ```
- [ ] **Test:** `yamllint gitops/workloads/layers/` — valid YAML
- [ ] **Test:** `argocd app sync root-app` — apps create and sync successfully

---

## Phase 5 — Vault Integration

- [ ] Vault policy: `workloads-text2pdf` — read `kv/data/text2pdf/*`
- [ ] K8s auth role: `text2pdf` — bound to SA in `backend-api`, `worker` namespaces
- [ ] Secrets in Vault: `kv/data/text2pdf/backend-api`, `kv/data/text2pdf/worker`
- [ ] Vault Agent injection annotations in Helm deployment templates
- [ ] Bootstrap script: `security/vault-bootstrap-workloads.sh`
- [ ] **Test:** `vault policy read workloads-text2pdf` — policy exists
- [ ] **Test:** Deploy pod with Vault annotations → verify `/vault/secrets/config` exists

---

## Phase 6 — MinIO Buckets

- [ ] Create `text2pdf-inputs` (7-day auto-purge)
- [ ] Create `text2pdf-outputs` (30-day retention)
- [ ] **Test:** `mc ls myminio/text2pdf-inputs` — bucket exists
- [ ] **Test:** Upload + lifecycle policy — verify 7-day rule applied

---

## Phase 7 — Observability

- [ ] Grafana dashboards:
  - Application: RPS, latency p50/p95/p99, error rate, queue depth
  - Worker: jobs/s, active pods, success rate, DLQ length
  - Business: documents created/failed, avg processing time
- [ ] Loki: structured log correlation by `request_id`
- [ ] PrometheusRules: `QueueBacklog`, `WorkerFailures`, `HighErrorRate`
- [ ] **Test:** Grafana API — dashboards provisioned and visible
- [ ] **Test:** Prometheus — targets are up (backend-api, worker, redis, cnpg)

---

## Phase 8 — Platform Hardening

- [ ] **PgBouncer**: enable CNPG connection pooler — `pooler.mode: transaction`, 2 instances
- [ ] NetworkPolicies:
  ```
  frontend → api
  api → postgres (5432)
  api → redis (6379)
  worker → redis (6379)
  worker → minio (9000)
  deny-all else
  ```
- [ ] Pod Security: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`
- [ ] Cosign signing in CI
- [ ] Velero backup schedules for workload namespaces
- [ ] **Test:** `kubectl exec` cross-namespace — blocked by NetworkPolicy
- [ ] **Test:** Velero backup created successfully
- [ ] **Test:** Trivy scan — zero HIGH/CRITICAL in chainguard images

---

## Phase 9 — CI/CD

**Goal:** Modern container build pipeline — BuildKit, GHA cache, Trivy, Cosign, GHCR.

- [ ] Local build via Taskfile:
  ```yaml
  build-api:
    cmds:
      - docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/atlas-idp/backend-api:dev apps/backend-api
  kind-load-api:
    cmds:
      - kind load docker-image ghcr.io/atlas-idp/backend-api:dev
  ```
- [ ] GitHub Actions pipeline:
  ```yaml
  name: Build & Deploy
  on:
    push:
      branches: [main]
      paths: ["apps/backend-api/**", "apps/worker/**"]
  jobs:
    test:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-go@v5
          with:
            go-version: "1.25"
        - run: go test ./... -race -shuffle=on -count=1
        - run: go test ./... -tags=integration
    build:
      needs: [test]
      steps:
        - uses: docker/setup-buildx-action@v3
        - uses: docker/login-action@v3
          with:
            registry: ghcr.io
        - uses: docker/build-push-action@v6
          with:
            push: true
            tags: |
              ghcr.io/atlas-idp/backend-api:sha-${{ github.sha }}
              ghcr.io/atlas-idp/backend-api:${{ github.ref_name }}
            cache-from: type=gha
            cache-to: type=gha,mode=max
            platforms: linux/amd64,linux/arm64
        - run: trivy image --severity HIGH,CRITICAL ghcr.io/atlas-idp/backend-api:sha-${{ github.sha }}
        - run: cosign sign --key env://COSIGN_KEY ghcr.io/atlas-idp/backend-api:sha-${{ github.sha }}
        # TODO: helm-lint + argocd-update
  ```
- [ ] Image tagging: `sha-{short}`, `v{semver}`, never `latest`
- [ ] Trivy image scan (HIGH/CRITICAL fail)
- [ ] Cosign signing + keyless (or key env var)
- [ ] SBOM generation (syft or trivy)
- [ ] k6 load tests (`apps/tests/load/`)
- [ ] DR runbook: backup → delete → restore → verify
- [ ] **Test:** GHA workflow runs green on PR
- [ ] **Test:** `cosign verify` passes on pushed image

---

## Time Allocation

| Area                                | %   |
| ----------------------------------- | --- |
| Go code (API + Worker)              | 15% |
| PDF signing (signer.go, verify)     |  5% |
| Helm charts                         | 15% |
| ArgoCD manifests + GitOps           | 20% |
| Vault policies + injection          | 15% |
| Monitoring/Logging/Tracing          | 15% |
| KEDA ScaledObject                   | 10% |
| NetworkPolicies + Velero + Security | 10% |
