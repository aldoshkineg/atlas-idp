# ADR-005: Управление инфраструктурными секретами через ESO + kms.vyrn.ru

## Статус

Принято

## Контекст

В репозитории есть два типа секретов:

1. **Инфраструктурные** — для установки platform-сервисов (MinIO, Redis, Velero, CNPG backup). Лежат в Helm values inline или raw Secret манифестах в git. 7 файлов с открытыми паролями.

2. **Прикладные** — для приложения Seal (postgres, redis, minio credentials, pdf-signer cert). Архитектурное решение для них — HashiCorp Vault Agent Injector (этап 2, отдельно).

Проблема: инфраструктурные секреты в открытом виде в публичном git-репозитории.

Доступен внешний Vault-сервер `kms.vyrn.ru:8200` (HTTPS, публичный сертификат) с уже существующим Vault token'ом.

## Решение

**External Secrets Operator (ESO)** читает секреты из `kms.vyrn.ru` и создаёт Kubernetes Secrets в кластере. Helm charts ссылаются на эти Secrets.

### Архитектура

```
┌─────────────────────────────────┐
│ kms.vyrn.ru:8200                │
│  secret/data/platform/minio     │
│    → rootUser, rootPassword     │
│  secret/data/platform/redis     │
│    → redis-password             │
│  secret/data/platform/backups   │
│    → ACCESS_KEY_ID,             │
│      ACCESS_SECRET_KEY          │
│  kv/data/seal/seal-api          │
│    → postgres_password,         │
│      redis_password             │
│  kv/data/seal/seal-worker       │
│    → minio_access_key,          │
│      minio_secret_key,          │
│      redis_password             │
│  kv/data/seal/pdf-signer        │
│    → cert, key                  │
└──────────────┬──────────────────┘
               │ ESO (ExternalSecret → watch)
               ▼
┌─────────────────────────────────┐
│ K8s Secret (в namespace сервиса)│
│  minio-credentials              │
│  velero-credentials              │
│  redis-auth                     │
│  production-db-backup           │
└──────────────┬──────────────────┘
               │ Helm chart / Deployment
               ▼
         Сервис использует Secret
```

### Аутентификация

ESO подключается к `kms.vyrn.ru` через **Vault Token**.

Token хранится в:

- GitHub Secrets (`VAULT_TOKEN`) — для CI
- K8s Secret `vault-token` в namespace `external-secrets` — создаётся через Terraform `kubernetes_secret` ресурс

ClusterSecretStore ссылается на этот K8s Secret:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: kms-vyrn
spec:
  provider:
    hashicorpVault:
      server: https://kms.vyrn.ru:8200
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

### Наполнение Vault

Первичное наполнение — **однократно вручную** через Vault CLI:

```bash
# Установить переменные окружения
export VAULT_ADDR=https://kms.vyrn.ru:8200
export VAULT_TOKEN=<token>

# Платформенные секреты
vault kv put secret/data/platform/minio \
  rootUser=minioadmin \
  rootPassword=minioadminpassword

vault kv put secret/data/platform/redis \
  redis-password=super-secret-redis

vault kv put secret/data/platform/backups \
  ACCESS_KEY_ID=minioadmin \
  ACCESS_SECRET_KEY=minioadminpassword

# Прикладные секреты (для этапа 2)
vault kv put kv/data/seal/seal-api \
  postgres_password=... \
  redis_password=...

vault kv put kv/data/seal/seal-worker \
  minio_access_key=minioadmin \
  minio_secret_key=minioadminpassword \
  redis_password=...

vault kv put kv/data/seal/pdf-signer \
  cert=@tls.crt \
  key=@tls.key
```

При повторном развёртывании (CI) секреты уже существуют — наполнение не требуется.

### Какие файлы меняются

#### 1. Новые компоненты (Argo CD Application)

`gitops/platform-kind/layers/security/external-secrets.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: platform-kind
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: 0.14.0
    helm:
      values: |
        installCRDs: true
        serviceAccount:
          create: true
          name: external-secrets
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### 2. ClusterSecretStore

`gitops/platform-kind/layers/security/resources/external-secrets/store.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: kms-vyrn
spec:
  provider:
    hashicorpVault:
      server: https://kms.vyrn.ru:8200
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

Управляется отдельным Application `external-secrets-store` (sync-wave 3, после ESO).

#### 3. Vault Token в кластер

Token создаётся через Terraform как K8s Secret:

```hcl
# infra/environments/dev/main.tf
resource "kubernetes_secret" "vault_token" {
  metadata {
    name      = "vault-token"
    namespace = "external-secrets"
  }
  data = {
    token = var.vault_token
  }
}
```

`vault_token` передаётся через `TF_VAR_vault_token` из GitHub Secrets.

#### 4. Helm charts: inline values → existingSecret

**`minio.yaml`:**

```yaml
# Было
values: |
  rootUser: minioadmin
  rootPassword: minioadminpassword

# Стало
values: |
  existingSecret: minio-credentials
```

Плюс ExternalSecret `gitops/platform-kind/layers/storage/resources/minio/external-secret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-credentials
  namespace: minio
spec:
  secretStoreRef:
    name: kms-vyrn
    kind: ClusterSecretStore
  target:
    name: minio-credentials
  data:
    - secretKey: rootUser
      remoteRef:
        key: secret/data/platform/minio
        property: rootUser
    - secretKey: rootPassword
      remoteRef:
        key: secret/data/platform/minio
        property: rootPassword
```

И Application `gitops/platform-kind/layers/storage/minio-secret.yaml` (sync-wave 4, до minio wave 5).

**`velero.yaml`:**

```yaml
# Было
credentials:
  useSecret: true
  secretContents:
    cloud: |
      [default]
      aws_access_key_id = minioadmin
      aws_secret_access_key = minioadminpassword

# Стало
credentials:
  useSecret: true
  existingSecret: velero-credentials
```

Плюс ExternalSecret + Application.

**`resources/redis/secret.yaml` — замена на ExternalSecret:**

```yaml
# Было
apiVersion: v1
kind: Secret
---
# Стало
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-auth
  namespace: redis
spec:
  secretStoreRef:
    name: kms-vyrn
    kind: ClusterSecretStore
  target:
    name: redis-auth
  data:
    - secretKey: redis-password
      remoteRef:
        key: secret/data/platform/redis
        property: redis-password
```

**`resources/postgres-cluster/backup-secret.yaml` — аналогично:**

```yaml
# Было
apiVersion: v1
kind: Secret
---
# Стало
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
---
data:
  - secretKey: ACCESS_KEY_ID
    remoteRef:
      key: secret/data/platform/backups
      property: ACCESS_KEY_ID
  - secretKey: ACCESS_SECRET_KEY
    remoteRef:
      key: secret/data/platform/backups
      property: ACCESS_SECRET_KEY
```

#### 5. `seal.yaml` (workloads)

На этапе 1 — не меняется (`vault.enabled: false`, secrets в `.Values.secrets.*`). На этапе 2 будет включён Vault Agent Injector с чтением из `kms.vyrn.ru`.

### Синк-вейвы

```
Wave 1: vault-operator, cert-manager
Wave 2: vault-secrets-webhook, cert-manager-issuers
Wave 3: external-secrets (ESO controller) + external-secrets-store (ClusterSecretStore)
Wave 4: minio-secret, velero-secret, redis-secret (ExternalSecret CRs)
Wave 5: minio, velero (Helm charts с existingSecret)
Wave 6: redis, kube-prometheus-stack
Wave 7+: остальные сервисы
```

### Pre-commit hooks

Изменений не требуется — все манифесты остаются валидным YAML (ExternalSecret — CRD с plain references, без секретных значений). `yamllint` и `trivy` работают штатно.

## Последствия

### Плюсы

- Секретов нет в git (ни открытых, ни зашифрованных)
- Vault — единый source of truth
- ESO умеет авто-рефреш при смене секретов в Vault
- Валидные YAML в git (читаемые diffs, linting работает)
- Централизованный аудит доступа к секретам (kms.vyrn.ru audit log)

### Минусы

- Нужно переписать 5+ манифестов (структурные изменения)
- Добавляется ESO controller (ещё один компонент в кластере)
- Зависимость времени синка: kms.vyrn.ru должен быть доступен
- Vault token в Terraform state (S3, для dev допустимо)
- Первичное наполнение Vault — ручное (однократно)

### Что дальше

- Этап 2: Vault Agent Injector для приложений Seal (чтение из `kv/data/seal/*` на kms.vyrn.ru)
- Автоматизация наполнения Vault через CI при смене значений

## Ссылки

- ADR-005-v1 (отклонён): SOPS + AGE (заменён на текущее решение)
- apps/ARCHITECTURE.md — Section 3 (Vault Agent Injection, этап 2)
- TODO.md:117 — исходное упоминание ESO (теперь реализуется)
- External Secrets Operator docs: https://external-secrets.io/latest/provider/hashicorp-vault/
