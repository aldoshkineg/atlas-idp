# Atlas IDP — Platform Engineering Showcase

## Positioning

This is **not "yet another CRUD in Go"**, but a production-ready Kubernetes platform showcase.
The **Seal** application is just a workload to demonstrate platform engineering practices:

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

## Application Architecture (Seal)

**Seal** — Document signing platform. Accepts text via web UI, queues jobs in Redis,
asynchronously generates PDFs with digital signatures, stores signed documents in MinIO.

```
                  Gateway API
                         │
          ┌──────────────┴──────────────┐
          │                             │
      Seal UI                    Seal API
   (Go + HTMX)                   (Go 1.26)
                                         │
                       ┌────────────────┼──────────────┐
                       │                │              │
                    Redis         PostgreSQL       Vault
                 (Bitnami)        (CNPG 17.6)   (Bank-Vaults)
                       │                              │
                       │                              │ PDF sign cert
                       ▼                              ▼
               Seal Worker ────── Cert Manager / Static
             (Go 1.26 + gofpdf          (apps/.certs/)
              + digitorus/pdfsign)
                       │
                       ▼
                     MinIO
                    (signed PDFs)
```

### Data Flow

```
User ──POST /documents──▶ Seal API
                            │
                            ├── INSERT into PostgreSQL (status: pending)
                            └── RPUSH job into Redis seal:jobs
                                    │
                                    ▼
                          Seal Worker (BLMOVE via KEDA)
                            │
                            ├── 1. Generate PDF (gofpdf)
                            ├── 2. Sign PDF (digitorus/pdfsign)
                            │     └── X.509 cert from Vault / file
                            ├── 3. Upload signed PDF to MinIO
                            └── 4. RPUSH result into Redis seal:results
                                          │
                                          ▼
                                  Seal API consumer (BLPOP seal:results)
                                          │
                                          └── UPDATE PostgreSQL (status: completed | failed)

User ──GET /documents/{id}                  ──▶ Seal UI ──▶ Seal API ──▶ PostgreSQL
User ──GET /documents/{id}/download         ──▶ Seal UI ──▶ Seal API ──▶ {"url"} ──▶ 303 redirect
                                                                                    ──▶ Gateway ──▶ MinIO
User ──GET /documents/{id}/verify           ──▶ Seal UI ──▶ Seal API
                            │
                            └── Check PG document status
                                └── completed → {valid: true}
                                └── other    → {valid: false, error: "not ready"}
```

### Components

| Component    | Stack                                                | Responsibility                                   |
| ------------ | ---------------------------------------------------- | ------------------------------------------------ |
| Seal UI      | Go 1.26 + chi + html/template + HTMX                 | Web UI: text input, status polling, PDF download |
| Seal API     | Go 1.26                                              | REST API, metadata in PG, task queue to Redis    |
| Seal Worker  | Go 1.26 + gofpdf + digitorus/pdfsign                 | Redis consumer, PDF generation, signing, MinIO upload (no PG access) |
| Signer       | digitorus/pdfsign, X.509 (RSA 2048, SHA-256)         | CMS/PAdES digital signature appended to PDF      |
| Cert Store   | File (dev) / Vault Agent (prod) / cert-manager       | X.509 signing certificate + RSA private key      |
| PostgreSQL   | CloudNativePG 17.6                                   | Document metadata                                |
| Redis        | Bitnami Redis 24.0.8                                 | Async task queue + status cache                  |
| MinIO        | S3-compatible storage                                | Signed PDF file storage                          |

---

## Technology Stack

### Languages

| Service     | Language                         | Runtime               |
| ----------- | -------------------------------- | --------------------- |
| Seal API    | Go 1.26                          | chainguard/static     |
| Seal Worker | Go 1.26                          | chainguard/static     |
| Seal UI     | Go 1.26                          | chainguard/static     |

### API Libraries (Go 1.26)

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

### UI Libraries (Go 1.26)

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
└── workloads/
    └── layers/
        ├── seal/         # AppProject + Application
```

**Demonstrates:** App-of-apps, sync-waves, multi-source, automated sync & prune, self-healing.

---

### 2. Gateway API

```
Gateway (nginx-gateway-fabric)
  ├── HTTPRoute ── seal.atlas     /  ──▶ Seal UI
  ├── HTTPRoute ── seal.atlas     /api/  ──▶ Seal API
  ├── HTTPRoute ── grafana.atlas  ──▶ Grafana
  ├── HTTPRoute ── vault.atlas    ──▶ Vault
  ├── HTTPRoute ── s3.atlas       ──▶ MinIO S3 API
  └── HTTPRoute ── console.s3.atlas ──▶ MinIO Console
```

**Demonstrates:** Modern Kubernetes ingress (not legacy Ingress), HTTPRoute, cross-namespace routing.

---

### 3. Secrets Management (Vault Agent Injection)

**Principle:** application reads configuration **from ENV only**. Where ENV values come from — `.env`, ConfigMap, Vault Agent — the application does not care.

```
Production chain:

Vault (Bank-Vaults)
  │  kv/data/seal/seal-api
  │  ├── postgres_password
  │  ├── redis_password
  │  kv/data/seal/seal-worker
  │  ├── minio_access_key
  │  ├── minio_secret_key
  │  └── redis_password
  │
  ▼
Vault Agent Sidecar (vault-secrets-webhook)
  │  annotations:
  │    vault.hashicorp.com/agent-inject: "true"
  │    vault.hashicorp.com/agent-inject-template-config: |
  │      export POSTGRES_PASSWORD=...
  │
  ▼
/vault/secrets/config (file with export statements)
  │
  ▼
Entrypoint: source /vault/secrets/config && exec /app
  │
  ▼
Environment Variables
  │
  ▼
Go Application (go-envconfig)
```

**Non-sensitive config** → ConfigMap (`envFrom: configMapRef`, host/port/log level)

**Sensitive config** → Vault → Vault Agent sidecar → sourced on startup → ENV

**⚠️ Caveat:** The base image `cgr.dev/chainguard/static:latest` has **no `/bin/sh`**. The vault-agent sourcing pattern requires a shell entrypoint. Currently `vault.enabled=false` in chart defaults; production Vault integration needs a different approach (e.g., `envsubst` init container or vault-csi-provider).

**Dev override:** When `vault.enabled=false`, secrets are provided via `.Values.secrets.*` (Helm `--set`), rendered as Kubernetes Secret objects. This breaks the zero-trust principle but is acceptable for development.

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
  ├── seal-outputs/       # Generated PDFs (30-day retention)
  └── cnpg-backups/       # WAL archives (forever)

Policies:
  ├── Lifecycle (auto-purge, archive tier)
  ├── Versioning
  └── IAM-style bucket policies
```

**Demonstrates:** S3-compatible storage, lifecycle management, backup storage integration.

---

### 5. Event-Driven Autoscaling (KEDA)

```
Redis (LIST: seal:jobs)
        │
        ▼
KEDA ScaledObject
  ├── minReplicaCount: 0
  ├── maxReplicaCount: 20
  └── triggers:
        └── redis-list
                │
                ▼
        Deployment: seal-worker
```

**Demonstrates:** Scale-to-zero, queue-based autoscaling, difference between HPA (API) and KEDA (worker).

---

### 6. Observability

#### Metrics (Prometheus)

| Component    | Metrics                                                                     | Exporter            |
| ------------ | --------------------------------------------------------------------------- | ------------------- |
| Seal API     | http_requests_total, http_request_duration_seconds, documents_created_total | Built-in (/metrics) |
| Seal Worker  | jobs_processed_total, jobs_failed_total, job_duration_seconds               | Built-in (/metrics) |
| Redis        | redis_exporter                                                              | Sidecar             |
| PostgreSQL   | CNPG metrics (port 9187)                                                    | Built-in            |
| MinIO        | Native Prometheus endpoint                                                  | Built-in            |
| KEDA         | keda_scaler_metrics_value                                                   | Built-in            |

#### Dashboards (Grafana)

| Dashboard            | Panels                                                        |
| -------------------- | ------------------------------------------------------------- |
| Application Overview | RPS, latency (p50/p95/p99), errors, queue depth, worker count |
| Infrastructure       | CPU, RAM, pods, node pressure                                 |
| Business             | Generated PDFs, failed jobs, avg processing time              |

#### Logging (Loki + Alloy)

```json
{
  "service": "seal-api",
  "request_id": "req_abc123",
  "document_id": "doc_uuid_xyz",
  "status": "completed",
  "duration_ms": 1450
}
```

**Correlation:** request_id across Seal API → Worker → MinIO → PG.

#### Tracing (OpenTelemetry + Tempo)

```
Seal UI ──▶ Seal API ──▶ Redis ──▶ Seal Worker ──▶ MinIO
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
  ├── Allow: Seal UI → Seal API
  ├── Allow: Seal API → PostgreSQL
  ├── Allow: Seal API → Redis
  ├── Allow: Seal Worker → Redis
  ├── Allow: Seal Worker → MinIO
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
cosign sign --key cosign.key ghcr.io/atlas-idp/seal-api:latest
```

#### Image Scanning

- Trivy in CI (HIGH/CRITICAL, fail on any)
- Trivy Operator in-cluster (runtime scanning)

---

### 9. Autoscaling (HPA + KEDA)

| Component    | Trigger            | Type               |
| ------------ | ------------------ | ------------------ |
| Seal API     | CPU / Memory       | HPA                |
| Seal Worker  | Redis queue length | KEDA ScaledObject  |
| Grafana      | CPU / Memory       | HPA                |
| Prometheus   | CPU / Memory       | HPA                |

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
    User     string `env:"POSTGRES_USER, default=seal"`
    Password string `env:"POSTGRES_PASSWORD, required"`
    DBName   string `env:"POSTGRES_DB, default=seal"`
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
# templates/deployment-api.yaml
annotations:
  {{- if .Values.vault.enabled }}
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "{{ .Values.vault.role }}"
  vault.hashicorp.com/agent-inject-secret-config: "{{ .Values.vault.paths.api }}"
  {{- end }}
```

Helm `values.yaml` contains **zero secrets**:

```yaml
config:
  postgres:
    host: production-db-rw.database.svc.cluster.local
    port: 5432
  redis:
    host: redis-master.redis.svc.cluster.local
    port: 6379
  minio:
    endpoint: minio.minio.svc.cluster.local:9000
  logLevel: info
  downloadUrlPrefix: https://s3.atlas
vault:
  enabled: true          # false = use .Values.secrets.* (dev only)
secrets: {}              # --set for dev; vault-agent for prod
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
task run-api     # go run ./apps/seal-api/cmd
task run-worker  # go run ./apps/seal-worker/cmd
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
tasks:
  build-api:
    desc: Build seal-api (build-arg APP_NAME=api)
    cmds:
      - docker buildx build --load --build-arg APP_NAME=api -t ghcr.io/atlas-idp/seal-api:dev ./seal-api
  build-worker:
    desc: Build seal-worker (build-arg APP_NAME=worker)
    cmds:
      - docker buildx build --load --build-arg APP_NAME=worker -t ghcr.io/atlas-idp/seal-worker:dev ./seal-worker
```

---

## Container Images

```dockerfile
FROM golang:1.26 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
ARG APP_NAME
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /app \
      ./cmd/${APP_NAME}
FROM cgr.dev/chainguard/static:latest
COPY --from=builder /app /app
ENTRYPOINT ["/app"]
```

### CI pipeline (GitHub Actions)

```yaml
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    push: true
    tags: ghcr.io/atlas-idp/seal-api:sha-${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
    platforms: linux/amd64,linux/arm64
```

Image tagging: `sha-{short}`, `v{semver}` — never `latest`.

Security: Trivy scan → Cosign sign → Syft SBOM → push.

---

## Repository Structure

```
apps/
├── seal-api/           # Go 1.26, REST API
│   ├── cmd/
│   │   └── api/
│   │       └── main.go
│   ├── internal/
│   │   ├── config.go
│   │   ├── handler.go
│   │   ├── repository.go
│   │   ├── queue.go
│   │   └── migrate.go
│   ├── migrations/
│   └── Dockerfile
├── seal-worker/        # Go 1.26, PDF generator + signer (blind, no PG)
│   ├── cmd/
│   │   └── worker/
│   │       └── main.go
│   ├── internal/
│   │   ├── config.go
│   │   ├── worker.go
│   │   ├── storage.go
│   │   ├── pdf.go
│   │   └── signer.go
│   └── Dockerfile
├── seal-ui/            # Go + HTMX
│   ├── cmd/
│   │   └── ui/
│   │       └── main.go
│   ├── internal/
│   │   ├── config.go
│   │   ├── server.go
│   │   ├── handlers/
│   │   ├── templates/
│   │   └── client/
│   └── Dockerfile
├── charts/
│   └── seal/           # Single Helm chart
├── tests/
│   ├── integration/    # testcontainers-go
│   └── load/           # k6 scripts
├── Taskfile.yml        # Workloads: build, test, dc-up, run-api, kind-load
└── TODO.md
```