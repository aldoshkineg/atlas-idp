# Atlas IDP — Implementation Roadmap

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

---

## 🔴 Critical (Security & Stability)

### 1. Security Hardening

- [x] **Trivy Operator**: Deploy for runtime vulnerability scanning
- [x] **Network Policies**: Deny-all default + allow rules for `platform-kind`/`workloads`
- [x] **ResourceQuota**: Limit CPU/Memory for `workloads` namespace

### 2. Disaster Recovery

- [x] **Velero Backup Schedules**: Daily backups for `platform-kind`/`workloads`
- [ ] **DR Runbook**: Document RTO/RPO and recovery procedure

---

## 🟡 High Priority (Core Functionality)

### 3. Autoscaling

- [x] **KEDA ScaledObject**: Configure Redis-triggered autoscaling for `worker`

### 4. Observability

- [x] **Grafana Tempo**: Deploy for distributed tracing
- [ ] **OpenTelemetry**: Instrument applications (backend-api/worker)

---

## 🟢 Medium Priority (Improvements)

### 5. Deployment Strategy

- [x] **Argo Rollouts**: Replace `backend-api` Deployment with Rollout CRD

### 6. Documentation

- [ ] **ADR**: Document architecture decisions (GitOps, Vault, KEDA)
- [ ] **Runbooks**: Create guides for ArgoCD bootstrap and Vault init

---

## ⚪ Low Priority (Nice-to-Have)

### 7. Developer Experience

- [ ] **Templates**: Standardized Go/Helm templates
- [ ] **Onboarding Guide**: Developer workflow documentation

### 8. Advanced Observability

- [ ] **Custom Dashboards**: App Performance and Queue Processing
- [ ] **SLO Alerts**: Configure Prometheus alerts for latency/error rates

---

## 📌 Next Sprint Focus (Top 5)

1. [x] Trivy Operator
2. [x] Network Policies
3. [x] KEDA ScaledObject
4. [x] Velero Backup Schedules
5. [x] ResourceQuota

---

## ✅ Completed

- [x] PostgreSQL ExternalSecret integration
- [x] CloudNativePG 17.6 with scheduled backups
- [x] Redis (Bitnami 24.0.8) with metrics
