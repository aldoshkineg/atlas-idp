# Workloads — Implementation Roadmap

> **Legend:** `[ ]` Planned

**Philosophy:** Application is a vehicle to demonstrate platform engineering.
15% Go code, 85% infrastructure (Helm, ArgoCD, Vault, KEDA, Observability, Security).

**Available in cluster:** CNPG 17.6, Redis, MinIO, KEDA, Vault (Bank-Vaults), Prometheus/Grafana/Loki/Alloy, ArgoCD.

---

## Phase 0 — Docker Compose

**Goal:** Local dev without Kubernetes.

- [ ] `docker-compose.yml` — postgres:17-alpine, redis:7-alpine, minio/minio
- [ ] `.env.example`
- [ ] `Taskfile.yml` targets: `dc-up`, `dc-down`, `run-api`, `run-worker`
- [ ] **Test:** `dc-up` starts all containers, services respond on expected ports

---

## Phase 1 — Backend API (Go 1.25)

**Stack:** chi, pgx, go-redis, go-envconfig, slog, prometheus, otel.

**Flat structure — no service layer, no telemetry package:**

```
apps/backend-api/
├── cmd/
│   ├── main.go
│   └── main_test.go          # smoke: startup, /healthz /readyz
├── internal/
│   ├── config.go
│   ├── config_test.go        # env parsing, defaults
│   ├── handler.go
│   ├── handler_test.go       # unit: testify/mock for repo + queue
│   ├── handler_integration_test.go  # build tag: integration, testcontainers
│   ├── repository.go
│   ├── repository_test.go    # unit: mock pgx
│   ├── queue.go
│   ├── queue_test.go         # unit: mock redis
│   ├── migrate.go
│   └── migrate_test.go       # embed FS reads correctly
├── migrations/
├── Dockerfile
└── go.mod
```

- [ ] `go mod init`, Config with go-envconfig
- [ ] `cmd/main.go` — startup, graceful shutdown, /healthz /readyz
- [ ] `migrate.go` — `//go:embed migrations/*.sql`, auto-migrate on start
- [ ] `repository.go` — pgx: CreateDocument, GetDocument, UpdateStatus
- [ ] `queue.go` — Redis: PushTask (RPUSH `text2pdf:jobs`)
- [ ] `handler.go` — chi:
  - `POST /api/v1/documents` → repo.Create + queue.PushTask, return {id}
  - `GET /api/v1/documents/{id}` → repo.GetDocument, return JSON
  - `GET /api/v1/documents/{id}/download` → presigned MinIO URL
  - Logging middleware (slog, request_id, method, path, duration)
  - Metrics middleware (http_requests_total, http_request_duration_seconds)
  - Tracing middleware (OpenTelemetry)
  - CORS middleware
- [ ] Dockerfile (multi-stage: `golang:1.25` → `cgr.dev/chainguard/static`, non-root, `-ldflags="-s -w"`, `--mount=type=cache` for go mod + build cache)
- [ ] **Test:** `go test ./...` — unit tests pass
- [ ] **Test:** `go test -tags=integration ./...` — testcontainers: real postgres + redis, full POST/GET flow

---

## Phase 2 — Worker (Go 1.25)

**Stack:** go-redis, pgx, minio-go, gofpdf, slog, prometheus, otel.

```
apps/worker/
├── cmd/
│   ├── main.go
│   └── main_test.go          # smoke: startup, graceful shutdown
├── internal/
│   ├── config.go
│   ├── config_test.go
│   ├── worker.go
│   ├── worker_test.go        # unit: BLPOP loop with mock repo/storage
│   ├── worker_integration_test.go  # build tag: integration, testcontainers
│   ├── pdf.go
│   ├── pdf_test.go           # text → PDF, check output bytes
│   ├── storage.go
│   ├── storage_test.go       # unit: mock minio
│   ├── repository.go
│   ├── repository_test.go    # unit: mock pgx
│   ├── migrate.go
│   └── migrate_test.go
├── Dockerfile
└── go.mod
```

- [ ] `go mod init`
- [ ] Config struct
- [ ] `cmd/main.go` — graceful shutdown, finish in-flight job
- [ ] `pdf.go` — gofpdf: text → PDF (minimal: A4, monospace, plain layout)
- [ ] `storage.go` — minio-go: Upload to `text2pdf-outputs/{id}.pdf`
- [ ] `repository.go` — pgx: UpdateDocumentStatus
- [ ] `worker.go` — main loop:
  ```go
  for {
      job := queue.Receive()    // BLPOP text2pdf:jobs
      pdf := pdf.Generate(job)  // text → PDF
      storage.Upload(job, pdf)  // MinIO
      repo.UpdateStatus(job)    // completed
  }
  ```
- [ ] Retry logic: 3 attempts, then push to `text2pdf:dlq`
- [ ] Metrics: `jobs_processed_total{status="ok|fail"}`, `job_duration_seconds`
- [ ] Dockerfile (same multi-stage pattern: chainguard, cache mounts, `-ldflags="-s -w"`)
- [ ] **Test:** `go test ./...` — unit tests pass
- [ ] **Test:** `go test -tags=integration ./...` — testcontainers: real redis + minio + postgres, full job lifecycle

---

## Phase 3 — Helm Charts

- [ ] `apps/charts/backend-api/`:
  - `Chart.yaml`, `values.yaml` (zero secrets — host/port/logLevel only)
  - `templates/deployment.yaml` — Vault Agent annotations, envFrom ConfigMap, probes, resources
  - `templates/service.yaml`
  - `templates/servicemonitor.yaml`
  - `templates/vault-role.yaml`
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
| Helm charts                         | 15% |
| ArgoCD manifests + GitOps           | 20% |
| Vault policies + injection          | 15% |
| Monitoring/Logging/Tracing          | 15% |
| KEDA ScaledObject                   | 10% |
| NetworkPolicies + Velero + Security | 10% |
