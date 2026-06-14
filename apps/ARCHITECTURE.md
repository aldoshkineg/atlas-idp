# Atlas IDP — Platform Engineering Showcase

## Positioning

This is **not "yet another CRUD in Go"**, but a production-ready Kubernetes platform showcase.
The text2pdf application is just a workload to demonstrate platform engineering practices:

- GitOps (Argo CD, app-of-apps, promotion)
- Gateway API (modern Kubernetes ingress)
- Secrets management (Vault Agent Injection, zero-trust)
- Event-driven autoscaling (KEDA, scale-to-zero)
- Observability (Prometheus, Grafana, Loki, Tempo)
- Disaster Recovery (Velero)
- Security (NetworkPolicies, Pod Security, Trivy, Cosign, RBAC)
- CI/CD (GitHub Actions, Trivy scans, container signing, GitOps sync)
- Testing (testcontainers, integration tests, k6 load tests)

---

## Application Architecture (text2pdf)

Business logic — minimal, just enough to exercise the platform:

```
                 Gateway API
                        │
         ┌──────────────┴──────────────┐
         │                             │
      Frontend                     Backend API
      (Go + HTMX)                    (Go 1.25)
                                        │
                      ┌────────────────┼──────────────┐
                      │                │              │
                   Redis         PostgreSQL       Vault
                (Bitnami)        (CNPG 17.6)   (Bank-Vaults)
                      │                              │
                      │                              │ PDF sign cert
                      ▼                              ▼
                 KEDA Worker ────── Cert Manager / Static
               (Go 1.25 + gofpdf          (apps/.certs/)
                + digitorus/pdfsign)
                      │
                      ▼
                    MinIO
                   (signed PDFs)
```

### Data Flow

```
User ──POST /documents──▶ Backend API
                            │
                            ├── INSERT into PostgreSQL (status: pending)
                            └── RPUSH job into Redis text2pdf:jobs
                                    │
                                    ▼
                          Worker (BLMOVE via KEDA)
                            │
                            ├── 1. Generate PDF (gofpdf)
                            ├── 2. Sign PDF (digitorus/pdfsign)
                            │     └── X.509 cert from Vault / file
                            ├── 3. Upload signed PDF to MinIO
                            └── 4. RPUSH result into Redis text2pdf:results
                                          │
                                          ▼
                                  Backend API consumer
                                  (BLPOP text2pdf:results)
                                          │
                                          └── UPDATE PostgreSQL (status: completed | failed)

User ──GET /documents/{id}                  ──▶ Frontend ──▶ Backend API ──▶ PostgreSQL
User ──GET /documents/{id}/download         ──▶ Frontend ──▶ Backend API ──▶ {"url"} ──▶ 303 redirect
                                                                                    ──▶ Gateway ──▶ MinIO
User ──GET /documents/{id}/verify           ──▶ Frontend ──▶ Backend API
                            │
                            └── Check PG document status
                                └── completed → {valid: true}
                                └── other    → {valid: false, error: "not ready"}
```

### Components

| Component   | Stack                                                | Responsibility                                   |
| ----------- | ---------------------------------------------------- | ------------------------------------------------ |
| Frontend    | Go 1.26 + chi + html/template + HTMX | Web UI: text input, status polling, PDF download |
| Backend API | Go 1.26                                              | REST API, metadata in PG, task queue to Redis    |
| Worker      | Go 1.26 + gofpdf + digitorus/pdfsign                 | Redis consumer, PDF generation, signing, MinIO upload (no PG access) |
| Signer      | digitorus/pdfsign, X.509 (RSA 2048, SHA-256)         | CMS/PAdES digital signature appended to PDF      |
| Cert Store  | File (dev) / Vault Agent (prod) / cert-manager       | X.509 signing certificate + RSA private key      |
| PostgreSQL  | CloudNativePG 17.6                                   | Document metadata                                |
| Redis       | Bitnami Redis 24.0.8                                 | Async task queue + status cache                  |
| MinIO       | S3-compatible storage                                | Signed PDF file storage                          |

---

## Technology Stack

### Languages

| Service     | Language                         | Runtime               |
| ----------- | -------------------------------- | --------------------- |
| Backend API | Go 1.26                          | distroless/chainguard |
| Worker      | Go 1.26                          | distroless/chainguard |
| Frontend    | Go 1.26                          | chainguard/static     |

### Backend Libraries (Go 1.26)

| Library                            | Purpose                                                  |
| ---------------------------------- | -------------------------------------------------------- |
| `go-chi/chi/v5`                    | HTTP router (stdlib net/http, lightweight)               |
| `jackc/pgx/v5`                     | PostgreSQL driver (native protocol, no ORM)              |
| `redis/go-redis/v9`                | Redis client                                             |
| `minio/minio-go/v7`                | MinIO / S3 client                                        |
| `golang-migrate/migrate/v4`        | Database migrations                                      |
| `sethvargo/go-envconfig`           | Configuration from environment                           |
| `prometheus/client_golang`         | Prometheus metrics                                       |
| `go.opentelemetry.io/otel`         | Distributed tracing                                      |
| `google/uuid`                      | UUID generation                                          |
| `log/slog`                         | Structured logging (stdlib)                              |
| `stretchr/testify`                 | Testing (assert, mock)                                   |
| `testcontainers/testcontainers-go` | Integration tests (real Postgres/Redis/MinIO on the fly) |

### Worker Libraries

| Library                     | Purpose                        |
| --------------------------- | ------------------------------ |
| `redis/go-redis/v9`         | BLMOVE queue consumer          |
| `minio/minio-go/v7`         | Upload to MinIO                |
| `jung-kurt/gofpdf`          | PDF generation                 |
| `digitorus/pdfsign`          | CMS/PAdES digital signing      |
| `sethvargo/go-envconfig`    | Configuration                  |
| `prometheus/client_golang`  | Metrics (+ signing metrics)    |
| `go.opentelemetry.io/otel`  | Tracing                        |
| `log/slog`                  | Structured logging             |

### Frontend Libraries (Go 1.26)

| Library                     | Purpose                        |
| --------------------------- | ------------------------------ |
| `go-chi/chi/v5`             | HTTP router                    |
| `sethvargo/go-envconfig`    | Configuration                  |
| `prometheus/client_golang`  | Metrics                        |
| `log/slog`                  | Structured logging             |

---

## Platform Capabilities Demonstrated

### 1. GitOps (Argo CD)

```
gitops/
├── bootstrap/            # Root app (app-of-apps)
├── platform-kind/        # Platform services
│   └── layers/
│       ├── bootstrap/    # AppProject (sync-wave -1)
│       ├── base/         # metrics-server, KEDA (wave 1)
│       ├── networking/   # Gateway API, nginx, routes (wave 0-6)
│       ├── security/     # cert-manager, Vault (wave 0-2)
│       ├── storage/      # CSI, MinIO, Velero (wave 1-4)
│       ├── data/         # CNPG, Redis (wave 1-6)
│       └── observability/# Prometheus, Loki, Alloy (wave 5-7)
└── workloads/            # Application workloads
    └── layers/
        ├── bootstrap/    # AppProject (sync-wave -1)
        ├── backend-api/
        ├── worker/
        └── cronjob/
```

**Demonstrates:** App-of-apps, sync-waves, multi-source, automated sync & prune, self-healing.

---

### 2. Gateway API

```
Gateway (nginx-gateway-fabric)
  ├── HTTPRoute ── app.demo.local ──▶ Frontend
  ├── HTTPRoute ── api.demo.local ──▶ Backend API
  ├── HTTPRoute ── grafana.demo.local ──▶ Grafana
  ├── HTTPRoute ── vault.demo.local ──▶ Vault
  └── HTTPRoute ── minio.demo.local ──▶ MinIO Console
```

**Demonstrates:** Modern Kubernetes ingress (not legacy Ingress), HTTPRoute, cross-namespace routing.

---

### 3. Secrets Management (Vault Agent Injection)

**Principle:** application reads configuration **from ENV only**. Where ENV values come from — `.env`, ConfigMap, Vault Agent — the application does not care.

```
Production chain:

Vault (Bank-Vaults)
  │  kv/data/text2pdf/backend
  │  ├── username
  │  ├── password
  │  ├── redis_password
  │  ├── minio_access_key
  │  └── minio_secret_key
  │
  ▼
Vault Agent Sidecar (vault-secrets-webhook)
  │  annotations:
  │    vault.hashicorp.com/agent-inject: "true"
  │    vault.hashicorp.com/agent-inject-template-config: |
  │      export POSTGRES_USER=...
  │      export POSTGRES_PASSWORD=...
  │
  ▼
/vault/secrets/config (file with export statements)
  │
  ▼
Entrypoint: source /vault/secrets/config && exec /app/backend
  │
  ▼
Environment Variables
  │
  ▼
Go Application (go-envconfig)
```

**Non-sensitive config** → ConfigMap (`envFrom: configMapRef`, host/port/log level)

**Sensitive config** → Vault → Vault Agent sidecar → sourced on startup → ENV

**Key points for CV:**

- No secrets in Git
- No secrets in Helm values
- No Kubernetes Secret objects for app secrets
- Secrets delivered at pod startup directly from Vault
- Zero-trust: application never handles secret material directly

---

### 4. Object Storage (MinIO)

```
Buckets:
  ├── text2pdf-inputs/     # Raw uploads (7-day TTL)
  ├── text2pdf-outputs/    # Generated PDFs (30-day retention)
  └── cnpg-backups/        # WAL archives (forever)

Policies:
  ├── Lifecycle (auto-purge, archive tier)
  ├── Versioning
  └── IAM-style bucket policies
```

**Demonstrates:** S3-compatible storage, lifecycle management, backup storage integration.

---

### 5. Event-Driven Autoscaling (KEDA)

```
Redis (LIST: task_queue)
        │
        ▼
KEDA ScaledObject
  ├── minReplicaCount: 0
  ├── maxReplicaCount: 20
  └── triggers:
        └── redis-list
                │
                ▼
        Deployment: worker
```

**Demonstrates:** Scale-to-zero, queue-based autoscaling, difference between HPA (API) and KEDA (worker).

---

### 6. Observability

#### Metrics (Prometheus)

| Component   | Metrics                                                                     | Exporter            |
| ----------- | --------------------------------------------------------------------------- | ------------------- |
| Backend API | http_requests_total, http_request_duration_seconds, documents_created_total | Built-in (/metrics) |
| Worker      | jobs_processed_total, jobs_failed_total, job_duration_seconds               | Built-in (/metrics) |
| Redis       | redis_exporter                                                              | Sidecar             |
| PostgreSQL  | CNPG metrics (port 9187)                                                    | Built-in            |
| MinIO       | Native Prometheus endpoint                                                  | Built-in            |
| KEDA        | keda_scaler_metrics_value                                                   | Built-in            |

#### Dashboards (Grafana)

| Dashboard            | Panels                                                        |
| -------------------- | ------------------------------------------------------------- |
| Application Overview | RPS, latency (p50/p95/p99), errors, queue depth, worker count |
| Infrastructure       | CPU, RAM, pods, node pressure                                 |
| Business             | Generated PDFs, failed jobs, avg processing time              |

#### Logging (Loki + Alloy)

```json
{
  "service": "backend-api",
  "request_id": "req_abc123",
  "document_id": "doc_uuid_xyz",
  "status": "completed",
  "duration_ms": 1450
}
```

**Correlation:** request_id across API → Worker → MinIO → PG.

#### Tracing (OpenTelemetry + Tempo)

```
Frontend ──▶ Backend API ──▶ Redis ──▶ Worker ──▶ MinIO
           trace_id=abc                    trace_id=abc
```

**Demonstrates:** Structured logging, log/metric/trace correlation, custom dashboards, SLO-based alerting.

---

### 7. Disaster Recovery (Velero)

```
Velero ──(MinIO storage)──▶ Backups
  ├── Daily: platform namespaces
  ├── Daily: workload namespaces
  └── Volume snapshots: PostgreSQL PVC, MinIO PVC

DR Runbook:
  1. kind delete cluster
  2. terraform apply (fresh cluster + ArgoCD)
  3. Velero restore --from-backup latest
  4. Validate application state
```

**Demonstrates:** Backup schedules, PVC snapshots, documented DR procedure, restore validation.

---

### 8. Security

#### Network Policies

```
Default deny-all per namespace
  ├── Allow: Frontend → Backend API
  ├── Allow: Backend API → PostgreSQL
  ├── Allow: Backend API → Redis
  ├── Allow: Worker → Redis
  ├── Allow: Worker → MinIO
  ├── Allow: Prometheus → all (metrics scrape)
  └── Deny: everything else
```

#### Pod Security

- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `securityContext.capabilities.drop: ALL`
- Chainguard / distroless base images (no shell, no package manager)

#### Image Signing (Cosign)

```bash
cosign sign --key cosign.key ghcr.io/atlas-idp/backend-api:latest
```

#### Image Scanning

- Trivy in CI (HIGH/CRITICAL, fail on any)
- Trivy Operator in-cluster (runtime scanning)

---

### 9. Autoscaling (HPA + KEDA)

| Component   | Trigger            | Type              |
| ----------- | ------------------ | ----------------- |
| Backend API | CPU / Memory       | HPA               |
| Worker      | Redis queue length | KEDA ScaledObject |
| Grafana     | CPU / Memory       | HPA               |
| Prometheus  | CPU / Memory       | HPA               |

**Demonstrates:** Understanding of when to use request-based (HPA) vs event-driven (KEDA) autoscaling.

---

### 10. CI/CD (GitHub Actions)

```
Push ──▶ lint ──▶ unit-test ──▶ integration-test ──▶ build-image
  ──▶ trivy-scan ──▶ cosign-sign ──▶ push-image ──▶ helm-lint
  ──▶ update-gitops ──▶ ArgoCD sync
```

---

### 11. Testing

| Type        | Tool                     | Scope                                    |
| ----------- | ------------------------ | ---------------------------------------- |
| Unit        | testing + testify/assert | Business logic, handlers                 |
| Mocking     | testify/mock             | External dependencies (DB, Redis, MinIO) |
| Integration | testcontainers-go        | Real Postgres/Redis/MinIO in containers  |
| E2E / Load  | k6                       | API endpoint benchmarks                  |

**Demonstrates:** Test pyramid, realistic integration testing, performance validation.

---

## Configuration Model

**Principle:** application always reads configuration from ENV. No files, no Vault SDK — only `os.Environ()`.

```go
type Config struct {
    HTTP      HTTPConfig
    Database  DatabaseConfig
    Redis     RedisConfig
    Minio     MinioConfig
    Telemetry TelemetryConfig
}

type HTTPConfig struct {
    Port      int    `env:"HTTP_PORT, default=8080"`
    LogLevel  string `env:"LOG_LEVEL, default=info"`
}

type DatabaseConfig struct {
    Host     string `env:"POSTGRES_HOST, default=localhost"`
    Port     int    `env:"POSTGRES_PORT, default=5432"`
    User     string `env:"POSTGRES_USER, default=text2pdf"`
    Password string `env:"POSTGRES_PASSWORD, required"`
    DBName   string `env:"POSTGRES_DB, default=text2pdf"`
}
```

Loaded exclusively from environment variables:

```go
envconfig.Process(ctx, &cfg)
```

### Source hierarchy

| Source                      | How                               | Use Case                                         |
| --------------------------- | --------------------------------- | ------------------------------------------------ |
| `.env` file                 | docker compose or `task run-api`  | Local development                                |
| ConfigMap                   | `envFrom: - configMapRef`         | Non-sensitive K8s config (host, port, log level) |
| Vault → Vault Agent sidecar | sourced at startup via entrypoint | Secrets (passwords, keys)                        |

### Helm deployment

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "text2pdf"
        vault.hashicorp.com/agent-inject-secret-config: "kv/data/text2pdf/{{ .Chart.Name }}"
        vault.hashicorp.com/agent-inject-template-config: |
          {{`{{- with secret "kv/data/text2pdf/backend" -}}`}}
          export POSTGRES_USER="{{`{{ .Data.data.username }}`}}"
          export POSTGRES_PASSWORD="{{`{{ .Data.data.password }}`}}"
          export REDIS_PASSWORD="{{`{{ .Data.data.redis_password }}`}}"
          export MINIO_ACCESS_KEY="{{`{{ .Data.data.minio_access_key }}`}}"
          export MINIO_SECRET_KEY="{{`{{ .Data.data.minio_secret_key }}`}}"
          {{`{{- end }}`}}
    spec:
      initContainers:
        - name: vault-agent
          ...
      containers:
        - name: {{ .Chart.Name }}
          command:
            - /bin/sh
            - -c
            - |
              source /vault/secrets/config
              exec /app/{{ .Chart.Name }}
          envFrom:
            - configMapRef:
                name: {{ .Chart.Name }}-config
```

Helm `values.yaml` contains **zero secrets**:

```yaml
# values.yaml — safe to commit to Git
config:
  postgres:
    host: cnpg-rw
    port: 5432
  redis:
    host: redis-master
    port: 6379
  minio:
    endpoint: minio:9000
  logLevel: info
  ```

---

## Local Development

### Docker Compose (lightweight)

```yaml
services:
  postgres:   # CNPG-compatible Postgres 17
  redis:      # Redis 7
  minio:      # S3-compatible storage
```

```bash
task dc-up       # start postgres, redis, minio
task run-api     # go run ./apps/backend-api/cmd
task run-worker  # go run ./apps/worker/cmd
```

### Kind Cluster (full platform)

```bash
make cluster-up    # kind cluster (root Makefile, platform)
make infra-apply   # Terraform + ArgoCD
task build-all     # build workload images (Taskfile)
task kind-load-all # load images into kind
```

---

## Build System

**Root Makefile** — platform tasks (cluster-up, infra-apply, pre-commit)

**Taskfile.yml** — workloads tasks (build, test, dc-up, run-api, kind-load)

```yaml
# Taskfile.yml
version: "3"

tasks:
  lint:
    cmds:
      - golangci-lint run ./...
  test:
    cmds:
      - go test ./... -race -shuffle=on
  test-integration:
    cmds:
      - go test ./tests/integration/...
  build-api:
    cmds:
      - docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/atlas-idp/backend-api:dev apps/backend-api
  build-worker:
    cmds:
      - docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/atlas-idp/worker:dev apps/worker
  kind-load:
    cmds:
      - kind load docker-image ghcr.io/atlas-idp/backend-api:dev
      - kind load docker-image ghcr.io/atlas-idp/worker:dev
```

---

## Container Images

```dockerfile
# Dockerfile (multi-stage with BuildKit cache)
FROM golang:1.25 AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /app .

FROM cgr.dev/chainguard/static:latest
COPY --from=builder /app /app
USER nonroot
ENTRYPOINT ["/app"]
```

Chainguard + BuildKit features:

- Build cache (go mod + go build) across CI runs via `--mount=type=cache`
- No shell, no package manager, zero CVEs
- Built-in nonroot user
- Signed by Chainguard (supply chain security)

### CI pipeline (GitHub Actions)

```yaml
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    push: true
    tags: ghcr.io/atlas-idp/backend-api:sha-${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
    platforms: linux/amd64,linux/arm64
```

Image tagging: `sha-{short}`, `v{semver}` — never `latest`.

Security: Trivy scan → Cosign sign → Syft SBOM → push.

---

## Production Considerations

### 1. Queue Reliability (Redis)

**Problem:** `BLPOP` removes a task from the queue before execution. Worker crash = data loss.

**Solution:** Use `BLMOVE` to atomically move tasks from `text2pdf:jobs` (pending) to `text2pdf:processing`. On completion, remove from `processing`. If worker crashes, a TTL/recovery mechanism returns items to the main queue.

Better alternative — **Redis Streams** with Consumer Groups:
- `XREADGROUP` with auto-claim for failed consumers
- `XPENDING` to inspect unacknowledged messages
- Built-in ACK mechanism (`XACK`)
- No manual re-queue logic needed

**Implementation:** Phase 2 Worker.

### 2. Safe Database Migrations

**Problem:** Auto-migration on API startup causes race conditions when HPA runs multiple replicas (table locks, duplicate migrations).

**Solution:** Remove migration from `cmd/main.go`. Create a separate **Kubernetes Job** for migrations, executed via **ArgoCD PreSync hook**:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: ghcr.io/atlas-idp/backend-api:sha-xxx
          command: ["/app", "migrate"]
      restartPolicy: Never
```

Migration binary embedded via `//go:embed`, triggered by `go run ./cmd migrate` subcommand (cobra or `os.Args[1]`).

**Implementation:** Phase 1 (binary supports `migrate` subcommand) + Phase 3 (Helm hook).

### 3. Connection Pool Management (PostgreSQL)

**Problem:** KEDA scaling to 20 workers + API pods can exhaust PostgreSQL connections.

**Solution (application level):**
```go
// pgxpool with hard limit
config, _ := pgxpool.ParseConfig(connString)
config.MaxConns = 5  // per pod
pool, _ := pgxpool.NewWithConfig(ctx, config)
```

**Solution (infrastructure level):** Enable **PgBouncer** in CNPG cluster:
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  instances: 1
  # ...
  monitoring:
    enablePodMonitor: true
  # PgBouncer connection pooler
  pooler:
    mode: transaction
    instances: 2
    template:
      spec:
        containers:
          - name: pgbouncer
            image: registry.developers.crunchydata.com/crunchydata/crunchy-pgbouncer:latest
```

**Implementation:** Phase 1 (MaxConns in code) + Phase 8 (PgBouncer in CNPG cluster).

### 4. Object Storage Resilience (MinIO)

**Problem:** Sudden worker scaling creates request storms, causing MinIO throttling or timeouts.

**Solution:** Exponential backoff in `minio-go` client:
```go
// minio-go v7 retry config
client, err := minio.New(endpoint, &minio.Options{
    Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
    Secure: false,
    // Built-in retry with exponential backoff
    Transport: &http.Transport{
        MaxIdleConns:    10,
        IdleConnTimeout: 30 * time.Second,
    },
})
```

On top of transport config, wrap uploads with retry logic:
```go
const maxRetries = 3
backoff := time.Second
for i := range maxRetries {
    _, err := client.PutObject(ctx, bucket, key, reader, size, opts)
    if err == nil {
        break
    }
    time.Sleep(backoff * (1 << i)) // 1s, 2s, 4s
}
```

**Implementation:** Phase 2 Worker.

```sql
CREATE TABLE documents (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status     VARCHAR(20) NOT NULL DEFAULT 'pending',
    input_text TEXT        NOT NULL,
    s3_path    VARCHAR(512),
    file_size  BIGINT      NOT NULL DEFAULT 0,
    error      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_created_at ON documents(created_at);
```

Status lifecycle: `pending → processing → completed | failed`

---

### 5. PDF Digital Signing

**Goal:** Every generated PDF carries a cryptographic signature proving authenticity and integrity.

**Stack:** `digitorus/pdfsign` (Go), RSA 2048, SHA-256, X.509 certificate from dev CA.

```
                    ┌─────────────┐
                    │  Raw PDF    │
                    │  (gofpdf)   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  Signer     │
                    │  pdfsign    │
                    │  CMS/PAdES  │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  Signed PDF │
                    │  (+ sig     │
                    │   appended) │
                    └──────┬──────┘
                           │
                           ▼
                       MinIO
```

**Key Management (Vault-first):**
- **Production:** Signing key never touches disk or git. Vault stores `kv/data/text2pdf/pdf-signer` with `cert` and `key` fields. Vault Agent injects into worker pod at `/vault/secrets/pdf-signer/`.
- **Dev / Docker Compose:** Local PEM files from `apps/.certs/tls.{crt,key}` mounted as volumes. The entire `apps/.certs/` directory is gitignored; certs are generated locally via `go-task gen-certs`.
- **Future:** cert-manager with Vault issuer for automatic certificate rotation.

**Verification (Backend API):**
```
GET /api/v1/documents/{id}/verify
  ├── Fetch document from PostgreSQL by ID
  ├── If status == "completed" → {valid: true}
  ├── If status != "completed" → {valid: false, error: "document not ready"}
  └── No MinIO client or PDF inspection in backend
```

**Metrics (Worker):**
- `pdf_sign_duration_seconds` — histogram of signing latency
- `pdf_sign_errors_total` — counter of signing failures (expired cert, malformed key)

**Implementation:** Phase 2 Worker (signer.go) + Phase 1 Backend API (verify endpoint).

---

## Repository Structure

```
atlas-idp/
├── apps/
│   ├── backend-api/       # Go 1.26, REST API
│   │   ├── cmd/
│   │   ├── internal/
│   │   │   ├── config.go
│   │   │   ├── handler.go
│   │   │   ├── repository.go
│   │   │   ├── queue.go
│   │   │   └── migrate.go
│   │   ├── migrations/
│   │   └── Dockerfile
│   ├── worker/            # Go 1.26, PDF generator + signer (blind, no PG)
│   │   ├── cmd/
│   │   ├── internal/
│   │   │   ├── config.go
│   │   │   ├── worker.go
│   │   │   ├── storage.go
│   │   │   ├── pdf.go
│   │   │   └── signer.go         # PDF signing (digitorus/pdfsign)
│   │   └── Dockerfile
│   ├── frontend/          # Go + HTMX
│   │   ├── cmd/
│   │   ├── internal/
│   │   │   ├── config.go
│   │   │   ├── server.go
│   │   │   ├── handlers/
│   │   │   ├── templates/
│   │   │   └── client/
│   │   └── Dockerfile
│   ├── cronjob/           # S3 cleanup / maintenance
│   ├── charts/            # Helm charts
│   │   ├── backend-api/
│   │   ├── worker/
│   │   ├── frontend/
│   │   └── cronjob/
│   └── tests/
│       ├── integration/   # testcontainers-go
│       └── load/          # k6 scripts
├── gitops/
│   ├── bootstrap/
│   ├── platform-kind/
│   └── workloads/
├── docs/
│   ├── ADR/
│   ├── runbooks/
│   └── diagrams/
├── infra/
├── apps/
│   ├── Taskfile.yml          # Workloads: build, test, dc-up, run-api, kind-load
│   └── tests/integration/docker-compose.yml
├── Makefile              # Platform: cluster-up, infra-apply, validate
```
