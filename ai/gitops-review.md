# GitOps Optimization Review

## Current Strengths

- Solid App-of-Apps pattern implementation
- Logical layer separation (networking, storage, security, data, observability)
- Proper resource exclusions in root-app (`values/`, `resources/` excluded)
- External Helms charts for prom-stack, loki, cnpg, minio, cert-manager, etc.
- Sync waves + `depends-on` for most components
- `ignoreDifferences` for webhook CA bundles and status fields
- `ServerSideApply` on CRD-heavy apps
- `RespectIgnoreDifferences` on observability apps
- ExternalSecrets for minio-auth, redis-auth (via Vault)

## Remaining Issues & Change Plan

### 2. Move all secrets from Git → `.env` (seeding via Vault)

**Problem:** plaintext credentials in Git:

- `gitops/platform-kind/layers/observability/values/prom-stack.yaml:40` — Grafana admin password
- `gitops/platform-kind/layers/storage/velero.yaml:50-54` — Velero MinIO credentials
- `gitops/platform-kind/layers/data/resources/postgres-cluster/backup-secret.yaml:10-11` — CNPG backup creds
- `tests/scripts/db-backup-test.sh:21` — test hardcodes minioadmin
- `tests/db-backup/backup-secret.yaml:8-9` — test secret

**Plan:**

| #   | File                                                                             | Action                                                                                                                          |
| --- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 2.1 | `gitops/platform-kind/layers/data/resources/postgres-cluster/backup-secret.yaml` | Remove, create ExternalSecret `production-db-backup` in `platform-secrets` (reference to `secret/platform/minio`)               |
| 2.2 | `gitops/platform-kind/layers/observability/values/prom-stack.yaml`               | Remove `adminPassword`, replace with `admin.existingSecret` + ExternalSecret for Grafana                                        |
| 2.3 | `gitops/platform-kind/layers/storage/velero.yaml`                                | Remove `credentials.secretContents`, replace with `credentials.existingSecret: velero-aws` + ExternalSecret                     |
| 2.4 | `gitops/platform-kind/layers/security/resources/platform-secrets/`               | Add ExternalSecret: `production-db-backup`, `grafana-admin`, `velero-aws`                                                       |
| 2.5 | `.env.example`                                                                   | Add `VL_GRAFANA_PASSWORD` (if a separate one is needed)                                                                         |
| 2.6 | `Makefile:126`                                                                   | Fix `vault-seed` — currently `seed-platform.sh seed` without seed-file; generate from `.env`                                    |
| 2.7 | `tests/scripts/db-backup-test.sh`                                                | Instead of hardcoding — read `minio-auth` from cluster: `kubectl -n minio get secret minio-auth -o jsonpath='{.data.rootUser}'` |
| 2.8 | `tests/db-backup/backup-secret.yaml`                                             | Remove; test creates secret dynamically                                                                                         |

---

### 3. Backups (CNPG backup stack)

**Problem:** backup secret in Git, test credentials hardcoded.
**Rationale:** `tests/scripts/db-backup-test.sh` tests backup/restore via MinIO. GitOps stack (`postgres-cluster`, `cluster.yaml`, `objectstore.yaml`, `scheduled-backup.yaml`) remains, secret source changes.

**Plan:**

| #   | File                                | Action                                                                                     |
| --- | ----------------------------------- | ------------------------------------------------------------------------------------------ |
| 3.1 | `gitops/.../backup-secret.yaml`     | Remove (replaced by ExternalSecret)                                                        |
| 3.2 | `gitops/.../cluster.yaml:28-33`     | `barmanObjectName: production-db-backup` — keep, correct                                   |
| 3.3 | `gitops/.../objectstore.yaml:13,16` | `s3Credentials.name: production-db-backup` — keep (ExternalSecret with that name)          |
| 3.4 | `tests/db-backup/`                  | Test `source-cluster.yaml`/`recovery-cluster.yaml` — change `backup-creds` → `minio-auth`? |

---

### 5. Improve pruning

**Problem:** not everywhere `RespectIgnoreDifferences` when `ignoreDifferences` is present; KEDA without finalizer/retry; no `PruneLast` for CRD Applications.

**Plan:**

| #    | File                                              | Action                                                          |
| ---- | ------------------------------------------------- | --------------------------------------------------------------- |
| 5.1  | `gitops/.../networking/nginx-gateway-fabric.yaml` | `syncOptions` + `RespectIgnoreDifferences=true`                 |
| 5.2  | `gitops/.../security/cert-manager.yaml`           | Same                                                            |
| 5.3  | `gitops/.../data/cnpg-operator.yaml`              | Same                                                            |
| 5.4  | `gitops/.../storage/snapshot-controller.yaml`     | Same                                                            |
| 5.5  | `gitops/.../networking/gateway-resources.yaml`    | Same                                                            |
| 5.6  | `gitops/.../networking/gateway-routes.yaml`       | Same                                                            |
| 5.7  | `gitops/.../base/keda.yaml`                       | + `RespectIgnoreDifferences=true`, + finalizer, + retry         |
| 5.8  | `gitops/.../networking/gateway-api-crds.yaml`     | annotation `argocd.argoproj.io/sync-options: PruneLast=true`    |
| 5.9  | `gitops/.../storage/snapshot-crds.yaml`           | Same                                                            |
| 5.10 | `gitops/bootstrap/platform-kind.yaml`             | Consider `orphanedResources: warn: true`                        |
| 5.11 | `gitops/bootstrap/root-app.yaml:22`               | Second source `workloads/layers` — add `exclude: "disabled/**"` |

---

### 6. Simplify dependency-graph

**Problem:** incorrect names in `depends-on`, missing dependencies, unnecessary serialization.

**Plan:**

| #   | File                                             | Line                                                                                                      | Was → Now |
| --- | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------- | --------- |
| 6.1 | `gitops/.../storage/minio.yaml:10`               | `platform-secrets-minio` → `platform-secrets`                                                             |
| 6.2 | `gitops/.../data/redis.yaml:10`                  | `platform-secrets-redis` → `platform-secrets`                                                             |
| 6.3 | `gitops/.../observability/alloy.yaml`            | none → `depends-on: loki`                                                                                 |
| 6.4 | `gitops/.../security/vault-secrets-webhook.yaml` | none → `depends-on: vault-operator`                                                                       |
| 6.5 | `gitops/.../data/postgres-cluster.yaml:10`       | `cloudnativepg-operator` → `cloudnativepg-operator, cloudnativepg-barman-plugin, minio, platform-secrets` |
| 6.6 | `gitops/.../data/redis.yaml:10`                  | `kube-prometheus-stack` — remove from depends-on if ServiceMonitor is disabled in chart; otherwise keep   |

---

### 7. Pin image versions

**Problem:** `latest` in Bank-Vaults, `debug: true` in webhook, Grafana `adminPassword` in Git.

**Plan:**

| #   | File                                                 | Line                                                                          | Action |
| --- | ---------------------------------------------------- | ----------------------------------------------------------------------------- | ------ |
| 7.1 | `gitops/.../vault/vault-cr.yaml:27`                  | `bankVaultsImage: ...:latest` → `:v1.33.1` (chart default)                    |
| 7.2 | `gitops/.../vault-secrets-webhook.yaml:23`           | `debug: true` → `false`                                                       |
| 7.3 | `gitops/.../observability/values/prom-stack.yaml:40` | `adminPassword` → `admin.existingSecret` (see 2.2)                            |
| 7.4 | `gitops/.../base/metrics-server.yaml`                | `--kubelet-insecure-tls` — keep for kind (see `values/metrics-server.yaml:3`) |

---

### Additional Items

| #   | File                                                 | Action                                           |
| --- | ---------------------------------------------------- | ------------------------------------------------ |
| 8.1 | `gitops/.../base/keda.yaml:66`                       | Check `enableClusterAapiAuthV1beta1` for typo    |
| 8.2 | `gitops/.../observability/values/prom-stack.yaml:58` | `storageClassName: standard` → `csi-hostpath-sc` |
| 8.3 | `gitops/.../observability/values/loki.yaml:11`       | `storageClassName: standard` → `csi-hostpath-sc` |
| 8.4 | `gitops/.../vault/vault-cr.yaml:43`                  | `storageClassName: standard` → `csi-hostpath-sc` |
| 8.5 | `gitops/.../security/platform-secrets.yaml`          | Add `destination.namespace`                      |
| 8.6 | `gitops/.../bootstrap/root-app.yaml`                 | Remove `jsonnet: {}` (unused)                    |

---

## Execution Order

1. **ExternalSecret** → `platform-secrets` (production-db-backup, grafana-admin, velero-aws)
2. **Remove** plaintext `backup-secret.yaml`, `prom-stack.yaml` adminPassword, velero credentials
3. **Fix** `depends-on` (6 items)
4. **RespectIgnoreDifferences** (6 items)
5. **PruneLast** (2 items) + KEDA finalizer/retry
6. **Pin Bank-Vaults** image + `debug: false`
7. **StorageClass** (3 items)
8. **Root-app** exclude disabled → validate
9. **Makefile** vault-seed fix
10. **Tests** — dynamic secret reading

> **Seal** — do not touch (per assignment).
> **Custom health checks** — do not write (per assignment).
