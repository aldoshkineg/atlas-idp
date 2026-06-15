# ADR-005: Управление инфраструктурными секретами через SOPS

## Статус

Принято

## Контекст

В репозитории есть два типа секретов:

1. **Инфраструктурные** — для установки platform-сервисов (MinIO, Redis, Velero, CNPG backup). Лежат в Helm values inline или raw Secret манифестах в git. Сейчас 7 файлов с открытыми паролями.

2. **Прикладные** — для приложения Seal (postgres, redis, minio credentials, pdf-signer cert). Архитектурное решение для них — HashiCorp Vault Agent Injector (этап 2, не реализован).

Текущая проблема: инфраструктурные секреты в открытом виде в git. Это неприемлемо для публичного репозитория.

Рассматривались варианты:
- **External Secrets Operator (ESO)** — требует развёртывания нового контроллера, ClusterSecretStore, переписывания всех манифестов, Seed Job для наполнения Vault, и не решает проблему бутстрапа (Vault пуст).
- **HashiCorp Vault Agent Injector** — архитектурное решение для прикладных секретов, неприменимо для инфраструктурных (Helm values).
- **Bank-Vaults webhook** — уже развёрнут, но не решает проблему инфраструктурных secrets.

## Решение

Использовать **Mozilla SOPS** с AGE-шифрованием для инфраструктурных секретов на этапе 1. Прикладные секреты (Seal) будут решаться отдельно на этапе 2.

### Механизм работы

```
Git (файлы зашифрованы SOPS)
  │
  ▼
Argo CD repo-server (встроенная расшифровка)
  │ configs.sops.enabled: true
  │ configs.sops.ageKey: <AGE_PRIVATE_KEY>
  ▼
Применяет расшифрованный манифест
  │
  ├── Application CRD → Helm chart с plaintext values
  └── Secret → Kubernetes Secret с plaintext данными
```

### Ключевая архитектура

AGE-ключ (`AGE_SECRET_KEY`) передаётся в Terraform через `TF_VAR_sops_age_private_key` из GitHub Secrets. Terraform записывает его в Argo CD config (`configs.sops.ageKey`). Расшифровка происходит на стороне repo-server при каждом синке — не требует дополнительных компонентов.

### Какие файлы шифруются (7 файлов)

| Файл | Тип |
|---|---|
| `gitops/platform-kind/layers/storage/minio.yaml` | Application + inline Helm values |
| `gitops/platform-kind/layers/storage/velero.yaml` | Application + inline Helm values |
| `gitops/workloads/layers/seal/seal.yaml` | Application + inline Helm values |
| `gitops/platform-kind/layers/data/resources/redis/secret.yaml` | Raw Secret |
| `gitops/platform-kind/layers/data/resources/postgres-cluster/backup-secret.yaml` | Raw Secret |
| `examples/cnpg-backup/backup-secret.yaml` | Raw Secret (пример) |
| `tests/db-backup/backup-secret.yaml` | Raw Secret (тест) |

### Что НЕ шифруется

- `gitops/bootstrap/root-app.yaml` — не содержит секретов
- Все `values/*.yaml` — конфигурация, не секреты
- `vault-cr.yaml` и прочие — конфиг, не секреты

### Pre-commit hooks

Добавить exclude для sops-файлов в `.pre-commit-config.yaml`, т.к. `yamllint` и `trivy` на зашифрованных файлах неинформативны.

### Что меняется в модулях

- `infra/modules/argocd-bootstrap/` — новый параметр `sops_age_key`, добавить `configs.sops` в Helm values
- `infra/environments/dev/main.tf` — передача `TF_VAR_sops_age_private_key`
- `.github/actions/terraform-kind/action.yml` — проброс `AGE_PRIVATE_KEY` из GitHub Secrets

## Последствия

### Плюсы
- Никаких новых компонентов в кластере (0 дополнительных контроллеров)
- Манифесты не меняют структуру — только содержимое шифруется
- Argo CD native support (не нужен plugin/sidecar)
- Единый механизм для platform и backup secrets
- SOPS-encrypted файлы можно использовать для seed'инга Vault на этапе 2

### Минусы
- Нечитаемые diffs в git (нужен `sops -d` для просмотра)
- AGE-ключ в Terraform state (S3, для dev допустимо)
- Pre-commit hooks нужно исключать для этих файлов
- Не решает доставку секретов в приложения (этап 2)

### Этап 2
Использовать SOPS же для seed-файла Vault: зашифрованный `vault-seed.yaml` содержит начальные значения для `kv/data/seal/*` и `kv/data/platform/*`. Kubernetes Job (sync-wave после Vault) расшифровывает и пишет `vault kv put`.

## Ссылки

- TODO.md — Phase 4/Data (CNPG backup secrets)
- apps/ARCHITECTURE.md — Section 3 (Vault Agent Injection, этап 2)
- TODO.md:117 — исходное упоминание ESO (заменено на SOPS)
