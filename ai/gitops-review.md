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

### 2. Вынос всех секретов из Git → `.env` (seeding via Vault)

**Проблема:** plaintext credentials в Git:

- `gitops/platform-kind/layers/observability/values/prom-stack.yaml:40` — Grafana admin password
- `gitops/platform-kind/layers/storage/velero.yaml:50-54` — Velero MinIO credentials
- `gitops/platform-kind/layers/data/resources/postgres-cluster/backup-secret.yaml:10-11` — CNPG backup creds
- `tests/scripts/db-backup-test.sh:21` — тест хардкодит minioadmin
- `tests/db-backup/backup-secret.yaml:8-9` — тестовый secret

**План:**

| #   | Файл                                                                             | Действие                                                                                                                   |
| --- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 2.1 | `gitops/platform-kind/layers/data/resources/postgres-cluster/backup-secret.yaml` | Удалить, создать ExternalSecret `production-db-backup` в `platform-secrets` (ссылка на `secret/platform/minio`)            |
| 2.2 | `gitops/platform-kind/layers/observability/values/prom-stack.yaml`               | Убрать `adminPassword`, заменить на `admin.existingSecret` + ExternalSecret для Grafana                                    |
| 2.3 | `gitops/platform-kind/layers/storage/velero.yaml`                                | Убрать `credentials.secretContents`, заменить на `credentials.existingSecret: velero-aws` + ExternalSecret                 |
| 2.4 | `gitops/platform-kind/layers/security/resources/platform-secrets/`               | Добавить ExternalSecret: `production-db-backup`, `grafana-admin`, `velero-aws`                                             |
| 2.5 | `.env.example`                                                                   | Добавить `VL_GRAFANA_PASSWORD` (если нужен отдельный)                                                                      |
| 2.6 | `Makefile:126`                                                                   | Починить `vault-seed` — сейчас `seed-platform.sh seed` без seed-файла; генерировать из `.env`                              |
| 2.7 | `tests/scripts/db-backup-test.sh`                                                | Вместо хардкода — читать `minio-auth` из кластера: `kubectl -n minio get secret minio-auth -o jsonpath='{.data.rootUser}'` |
| 2.8 | `tests/db-backup/backup-secret.yaml`                                             | Удалить; тест создаёт secret динамически                                                                                   |

---

### 3. Бэкапы (CNPG backup stack)

**Проблема:** backup secret в Git, test credentials хардкодом.
**Обоснование:** `tests/scripts/db-backup-test.sh` тестирует backup/restore через MinIO. GitOps-стек (`postgres-cluster`, `cluster.yaml`, `objectstore.yaml`, `scheduled-backup.yaml`) остаётся, источник secret меняется.

**План:**

| #   | Файл                                | Действие                                                                                       |
| --- | ----------------------------------- | ---------------------------------------------------------------------------------------------- |
| 3.1 | `gitops/.../backup-secret.yaml`     | Удалить (замена на ExternalSecret)                                                             |
| 3.2 | `gitops/.../cluster.yaml:28-33`     | `barmanObjectName: production-db-backup` — остаётся, корректно                                 |
| 3.3 | `gitops/.../objectstore.yaml:13,16` | `s3Credentials.name: production-db-backup` — остаётся (ExternalSecret с таким именем)          |
| 3.4 | `tests/db-backup/`                  | Тестовые `source-cluster.yaml`/`recovery-cluster.yaml` — менять `backup-creds` → `minio-auth`? |

---

### 5. Улучшение pruning

**Проблема:** не везде `RespectIgnoreDifferences` при наличии `ignoreDifferences`; KEDA без finalizer/retry; нет `PruneLast` для CRD-приложений.

**План:**

| #    | Файл                                              | Действие                                                             |
| ---- | ------------------------------------------------- | -------------------------------------------------------------------- |
| 5.1  | `gitops/.../networking/nginx-gateway-fabric.yaml` | `syncOptions` + `RespectIgnoreDifferences=true`                      |
| 5.2  | `gitops/.../security/cert-manager.yaml`           | То же                                                                |
| 5.3  | `gitops/.../data/cnpg-operator.yaml`              | То же                                                                |
| 5.4  | `gitops/.../storage/snapshot-controller.yaml`     | То же                                                                |
| 5.5  | `gitops/.../networking/gateway-resources.yaml`    | То же                                                                |
| 5.6  | `gitops/.../networking/gateway-routes.yaml`       | То же                                                                |
| 5.7  | `gitops/.../base/keda.yaml`                       | + `RespectIgnoreDifferences=true`, + finalizer, + retry              |
| 5.8  | `gitops/.../networking/gateway-api-crds.yaml`     | annotation `argocd.argoproj.io/sync-options: PruneLast=true`         |
| 5.9  | `gitops/.../storage/snapshot-crds.yaml`           | То же                                                                |
| 5.10 | `gitops/bootstrap/platform-kind.yaml`             | Рассмотреть `orphanedResources: warn: true`                          |
| 5.11 | `gitops/bootstrap/root-app.yaml:22`               | Второй source `workloads/layers` — добавить `exclude: "disabled/**"` |

---

### 6. Упрощение dependency-graph

**Проблема:** неверные имена в `depends-on`, недостающие зависимости, лишняя сериализация.

**План:**

| #   | Файл                                             | Строка                                                                                                    | Было → Стало |
| --- | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------- | ------------ |
| 6.1 | `gitops/.../storage/minio.yaml:10`               | `platform-secrets-minio` → `platform-secrets`                                                             |
| 6.2 | `gitops/.../data/redis.yaml:10`                  | `platform-secrets-redis` → `platform-secrets`                                                             |
| 6.3 | `gitops/.../observability/alloy.yaml`            | нет → `depends-on: loki`                                                                                  |
| 6.4 | `gitops/.../security/vault-secrets-webhook.yaml` | нет → `depends-on: vault-operator`                                                                        |
| 6.5 | `gitops/.../data/postgres-cluster.yaml:10`       | `cloudnativepg-operator` → `cloudnativepg-operator, cloudnativepg-barman-plugin, minio, platform-secrets` |
| 6.6 | `gitops/.../data/redis.yaml:10`                  | `kube-prometheus-stack` — убрать из depends-on, если выключить ServiceMonitor в chart; иначе оставить     |

---

### 7. Фиксация версий images

**Проблема:** `latest` в Bank-Vaults, `debug: true` в webhook, Grafana `adminPassword` в Git.

**План:**

| #   | Файл                                                 | Строка                                                                            | Действие |
| --- | ---------------------------------------------------- | --------------------------------------------------------------------------------- | -------- |
| 7.1 | `gitops/.../vault/vault-cr.yaml:27`                  | `bankVaultsImage: ...:latest` → `:v1.33.1` (chart default)                        |
| 7.2 | `gitops/.../vault-secrets-webhook.yaml:23`           | `debug: true` → `false`                                                           |
| 7.3 | `gitops/.../observability/values/prom-stack.yaml:40` | `adminPassword` → `admin.existingSecret` (см. 2.2)                                |
| 7.4 | `gitops/.../base/metrics-server.yaml`                | `--kubelet-insecure-tls` — оставить для kind (cм. `values/metrics-server.yaml:3`) |

---

### Дополнительно

| #   | Файл                                                 | Действие                                             |
| --- | ---------------------------------------------------- | ---------------------------------------------------- |
| 8.1 | `gitops/.../base/keda.yaml:66`                       | Проверить `enableClusterAapiAuthV1beta1` на опечатку |
| 8.2 | `gitops/.../observability/values/prom-stack.yaml:58` | `storageClassName: standard` → `csi-hostpath-sc`     |
| 8.3 | `gitops/.../observability/values/loki.yaml:11`       | `storageClassName: standard` → `csi-hostpath-sc`     |
| 8.4 | `gitops/.../vault/vault-cr.yaml:43`                  | `storageClassName: standard` → `csi-hostpath-sc`     |
| 8.5 | `gitops/.../security/platform-secrets.yaml`          | Добавить `destination.namespace`                     |
| 8.6 | `gitops/.../bootstrap/root-app.yaml`                 | Убрать `jsonnet: {}` (unused)                        |

---

## Порядок выполнения

1. **ExternalSecret** → `platform-secrets` (production-db-backup, grafana-admin, velero-aws)
2. **Удалить** plaintext `backup-secret.yaml`, `prom-stack.yaml` adminPassword, velero credentials
3. **Починить** `depends-on` (6 шт.)
4. **RespectIgnoreDifferences** (6 шт.)
5. **PruneLast** (2 шт.) + KEDA finalizer/retry
6. **Pin Bank-Vaults** image + `debug: false`
7. **StorageClass** (3 шт.)
8. **Root-app** exclude disabled → validate
9. **Makefile** vault-seed fix
10. **Tests** — dynamic secret чтение

> **Seal** — не трогаем (по заданию).
> **Custom health checks** — не пишем (по заданию).
