# Atlas IDP Roadmap

# Phase 6 — Platform Foundation

**Goal:** Prepare the platform for running production-like workloads.

## Platform Components
* [x] Deploy KEDA via Helm (sync-wave 8, keda namespace)
* [x] Fix vault-secrets-webhook HPA configuration (added `resources.requests.cpu`)[cite: 1]
* [x] Validate KEDA metrics pipeline

## Namespace Architecture
* [x] Create platform namespace[cite: 1]
* [x] Create workloads namespace[cite: 1]
* [x] Create observability namespace
* [x] Create data namespace

## GitOps Improvements
* [x] Separate platform and workload applications[cite: 1]
* [x] Introduce workload-specific ArgoCD structure[cite: 1]
* [x] Standardize labels and annotations

## Deployment Standards
* [~] Create reusable Helm values template (per-app values files exist, no global template yet)
* [x] Define resource requests defaults
* [x] Define resource limits defaults
* [x] Define workload conventions (including global `topologySpreadConstraints` to fix kind node pod distribution imbalance)[cite: 1]

## Documentation
* [ ] Update architecture diagram[cite: 1]
* [ ] Create deployment flow diagram[cite: 1]
* [ ] Create GitOps workflow diagram[cite: 1]

**Success Criteria:**
* Platform fully managed by ArgoCD[cite: 1] — ✅
* Workloads isolated from platform services[cite: 1] — ✅
* Deployment standards documented — partial

---

# Phase 7 — Stateful Services Layer

**Goal:** Provide shared platform services for applications.

## PostgreSQL
* **Technology:** CloudNativePG 17.6 (replaces Bitnami PostgreSQL)
* **Tasks:**
  * [x] Deploy CNPG Operator (1.29.1, cnpg-system namespace)
  * [x] Create cluster `production-db` (1 instance, csi-hostpath-sc, 256Mi)
  * [x] Configure probes (built-in CNPG)
  * [x] WAL archiving via barman-cloud plugin → MinIO `cnpg-backups`
  * [x] ScheduledBackup `production-db-weekly` (Sundays at 03:00)
  * [x] PodMonitor for Prometheus metrics (port 9187, `health=up` verified)
  * [x] Backup/restore test: 7/7 PASS
  * [ ] Vault secret injection for PG credentials

## Redis
* **Technology:** Redis (Bitnami Redis Chart 24.0.8)
* **Tasks:**
  * [x] Deploy Redis (standalone, redis namespace)
  * [x] Enable persistence (256Mi, csi-hostpath-sc)
  * [x] Deploy redis-exporter (built-in Bitnami chart)
  * [x] Create ServiceMonitor (monitoring namespace, 30s interval)
  * [ ] Enable AOF persistence for queue stability
  * [ ] Vault secret injection for Redis password

## MinIO
* **Technology:** MinIO (S3-compatible object storage)[cite: 1, 2]
* **Tasks:**
  * [x] Deploy MinIO (sync-wave 3, minio namespace)
  * [x] Configure persistence[cite: 1]
  * [x] Expose S3 endpoint internally[cite: 1] (via Gateway API HTTPRoute)
  * [ ] Create application buckets (`text2pdf-inputs`, `text2pdf-outputs`)
  * [ ] Configure lifecycle policies (auto-purge raw inputs after 7 days)
  * [ ] Vault secret injection for MinIO credentials

## Vault Integration
* [ ] Configure PostgreSQL secrets (backup secret still hardcoded in gitops)
* [ ] Configure Redis secrets
* [ ] Configure MinIO secrets
* [ ] Configure application secret paths (`secret/data/workloads/*`)[cite: 1]

**Success Criteria:**
* PostgreSQL operational[cite: 1] — ✅ (CNPG)
* Redis operational — ✅
* MinIO operational[cite: 1] — ✅
* Secrets delivered from Vault[cite: 1] — ❌

---

# Phase 8 — Application Layer

**Goal:** Deploy a complete event-driven application.

**Application:** Text → PDF Platform[cite: 1]