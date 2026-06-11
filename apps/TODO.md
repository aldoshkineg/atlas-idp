# Atlas IDP Roadmap

# Phase 6 — Platform Foundation

**Goal:** Prepare the platform for running production-like workloads.

## Platform Components
* [ ] Deploy KEDA via Helm
* [ ] Fix vault-secrets-webhook HPA configuration (add missing `resources.requests.cpu`)[cite: 1]
* [ ] Validate KEDA metrics pipeline

## Namespace Architecture
* [ ] Create platform namespace[cite: 1]
* [ ] Create workloads namespace[cite: 1]
* [ ] Create observability namespace
* [ ] Create data namespace

## GitOps Improvements
* [ ] Separate platform and workload applications[cite: 1]
* [ ] Introduce workload-specific ArgoCD structure[cite: 1]
* [ ] Standardize labels and annotations

## Deployment Standards
* [ ] Create reusable Helm values template
* [ ] Define resource requests defaults
* [ ] Define resource limits defaults
* [ ] Define workload conventions (including global `topologySpreadConstraints` to fix kind node pod distribution imbalance)[cite: 1]

## Documentation
* [ ] Update architecture diagram[cite: 1]
* [ ] Create deployment flow diagram[cite: 1]
* [ ] Create GitOps workflow diagram[cite: 1]

**Success Criteria:**
* Platform fully managed by ArgoCD[cite: 1]
* Workloads isolated from platform services[cite: 1]
* Deployment standards documented

---

# Phase 7 — Stateful Services Layer

**Goal:** Provide shared platform services for applications.

## PostgreSQL
* **Technology:** PostgreSQL 16 (Bitnami PostgreSQL Chart)
* **Tasks:**
  * [ ] Deploy PostgreSQL[cite: 1]
  * [ ] Configure persistent storage[cite: 1]
  * [ ] Configure readiness probe[cite: 1]
  * [ ] Configure liveness probe[cite: 1]
  * [ ] Configure startup probe[cite: 1]
  * [ ] Configure Velero pre-backup hooks (`pre.hook.backup.velero.io` inside pod annotations for consistent `pg_dump`)
  * [ ] Deploy postgres-exporter
  * [ ] Create ServiceMonitor

## Redis
* **Technology:** Redis (Bitnami Redis Chart)
* **Tasks:**
  * [ ] Deploy Redis
  * [ ] Enable AOF persistence
  * [ ] Deploy redis-exporter
  * [ ] Create ServiceMonitor

## MinIO
* **Technology:** MinIO (S3-compatible object storage)[cite: 1, 2]
* **Tasks:**
  * [ ] Deploy MinIO[cite: 1]
  * [ ] Create application buckets (`text2pdf-inputs`, `text2pdf-outputs`)
  * [ ] Configure persistence[cite: 1]
  * [ ] Configure lifecycle policies (auto-purge raw inputs after 7 days)
  * [ ] Expose S3 endpoint internally[cite: 1]

## Vault Integration
* [ ] Configure PostgreSQL secrets[cite: 1]
* [ ] Configure Redis secrets
* [ ] Configure MinIO secrets
* [ ] Configure application secret paths (`secret/data/workloads/*`)[cite: 1]

**Success Criteria:**
* PostgreSQL operational[cite: 1]
* Redis operational
* MinIO operational[cite: 1]
* Secrets delivered from Vault[cite: 1]

---

# Phase 8 — Application Layer

**Goal:** Deploy a complete event-driven application.

**Application:** Text → PDF Platform[cite: 1]
