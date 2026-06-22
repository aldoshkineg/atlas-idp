# Workloads — Golden Path Implementation

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

> **Архитектурное решение:**
> - Один общий CNPG `production-db` кластер на все workloads. Каждому проекту — своя БД
> - Один общий Redis на весь кластер
> - Один общий MinIO на весь кластер
> - Grafana — shared viewer account (не per-workload)

---

## Структура workload

```
workloads/<group>/<app>/
├── app.yaml                    # ArgoCD Application → внешний репо (helm/source)
├── gateway.yaml                # (опц.) HTTPRoute + Certificate (---)
├── .secret-seed                # шаблон env vars для atlasctl seed (gitignored)
├── vault/
│   ├── policy.hcl
│   ├── k8s-auth-role.yaml
│   └── seed-mapping.conf
├── secrets.yaml                # (опц.) ExternalSecrets: database + s3 + redis
├── infra/
│   ├── resource-quota.yaml     # (опц.)
│   └── network-policy.yaml     # (опц.)
├── monitoring/
│   ├── pod-monitor.yaml        # (опц.)
│   └── prometheus-rule.yaml    # (опц.)
├── autoscaling/
│   └── scaled-object.yaml      # (опц.) KEDA
└── rollouts/
    └── rollout.yaml            # (опц.) Argo Rollouts
```

**Фичи** определяются по наличию директорий/файлов:
`secrets.yaml`, `gateway.yaml`, `monitoring/`, `autoscaling/`, `rollouts/`

---

## Phase 1 — templates/gold/

**Цель:** Финальный состав шаблонов для `atlasctl new`.

```
templates/gold/
├── app.yaml.tmpl                    → workloads/<g>/<a>/app.yaml
├── gateway.yaml.tmpl                → workloads/<g>/<a>/gateway.yaml (опц.)
├── secrets.yaml.tmpl                → workloads/<g>/<a>/secrets.yaml (DB + S3 + Redis)
├── .secret-seed.tmpl                → workloads/<g>/<a>/.secret-seed
├── vault/
│   ├── policy.hcl.tmpl
│   ├── k8s-auth-role.yaml.tmpl
│   └── seed-mapping.conf.tmpl
├── monitoring/
│   ├── pod-monitor.yaml.tmpl
│   └── prometheus-rule.yaml.tmpl
└── infra/
    ├── resource-quota.yaml.tmpl
    └── network-policy.yaml.tmpl
```

- [x] **Создан `secrets.yaml.tmpl`** — объединяет ExternalSecrets для production-db, MinIO, Redis
- [x] **Удалены** `database/`, `s3/`, `redis/` — заменены на `secrets.yaml`
- [x] **Обновлён `vault/seed-mapping.conf.tmpl`** — маппинги `db_*`, `s3_*`, `redis_*` по умолчанию

---

## Команды atlasctl

| Команда | Что делает | Флаги |
|---------|------------|-------|
| `atlasctl new <app> --group <g>` | Создаёт `workloads/<group>/<app>/` + шаблоны | `--repo`, `--path`, `--helm`, `--db`, `--s3`, `--redis`, `--monitoring`, `--ingress`, `--keda`, `--rollouts` |
| `atlasctl seed <group>/<app>` | Провиженинг DB + bucket + Vault | `--force` (пропустить валидацию), `--dry-run` |
| `atlasctl enable <group>/<app>` | Создаёт gitops Application + gateway listener | `--sync`, `--push`, `--dry-run`, `--force`, `-y` |
| `atlasctl disable <group>/<app>` | Удаляет gitops Application + gateway listener | `--sync`, `--push`, `--dry-run`, `--keep-workload`, `-y` |
| `atlasctl status <group>/<app>` | Статус workload | `--json` |
| `atlasctl list` | Список всех workloads | `--json` |

---

## Workflow dev-а

```bash
# 1. Создать workload
atlasctl new seal --group aldoshkineg --repo https://github.com/aldoshkineg/atlas-idp-seal.git --db --s3 --ingress --monitoring

# 2. Настроить app.yaml, gateway.yaml, .secret-seed (пароли уже сгенерированы)

# 3. Один раз: провиженинг БД + бакет + Vault
atlasctl seed aldoshkineg/seal

# 4. Включить в GitOps
atlasctl enable aldoshkineg/seal --dry-run   # просмотр
atlasctl enable aldoshkineg/seal --sync --push  # применить

# 5. Статус
atlasctl status aldoshkineg/seal

# 6. Отключить (при необходимости)
atlasctl disable aldoshkineg/seal --dry-run
atlasctl disable aldoshkineg/seal --sync --push
```

---

## Phase 2 — `atlasctl new` ✓

**Цель:** Создаёт структуру `workloads/<group>/<app>/` из шаблонов.

- [x] Реализовать `cmd_new()`:
  - Создаёт `workloads/<group>/<app>/`
  - Копирует шаблоны из `templates/gold/` (выборочно, по флагам)
  - Создаёт `.secret-seed` с переменными для DB/S3/Redis
  - `app.yaml` → `spec.source.repoURL`, `path`, `helm` из флагов
  - `spec.destination.namespace` = `<group>-<app>` (или кастомный из `--namespace`)
  - Не трогает `gitops/`
- [x] **Обновить next steps** в выводе `new`
- [x] Проверить, что `atlasctl new seal --group aldoshkineg --repo ...` не трогает `gitops/`

---

## Phase 3 — `atlasctl seed <group>/<app>` ✓

**Цель:** Провиженинг инфраструктуры и запись секретов в Vault.

- [x] Реализовать `cmd_seed()`:
  - Валидация `.secret-seed` существует и не пуст
  - Валидация структуры (app.yaml, vault/)
  - Чтение `seed-mapping.conf` — какие ключи куда маппятся
- [x] **Провиженинг PostgreSQL:**
  - Идемпотентно: CREATE DATABASE, CREATE USER / ALTER USER, GRANT
  - Через `kubectl exec production-db-1 -n database`
- [x] **Провиженинг MinIO:**
  - Идемпотентно: создание бакета, пользователя, назначение readwrite policy
  - Через `kubectl exec minio-0 -n minio -- mc ...`
- [x] **Redis:** Пароль читается из platform secret `redis-auth` и записывается в Vault
- [x] **Запись в Vault:** через `vault kv put` (локально или через `kubectl exec vault-0`)
- [x] Идемпотентность: DB/user/bucket проверяются перед созданием
- [x] `--dry-run`: показать что будет создано
- [x] `--force`: пропустить валидацию
- [ ] **Testing:** протестировать на живом кластере (Live Cluster Test)

---

## Phase 4 — `atlasctl enable <group>/<app>` ✓

**Цель:** Создать ArgoCD Application CR + gateway listener.

- [x] Реализовать `cmd_enable()`:
  - Валидация (если не `--force`): workload существует, app.yaml есть, не за-enable-ен
  - Чтение namespace из `app.yaml`: `yq eval '.spec.destination.namespace'`
  - Чтение hostname из `gateway.yaml`: `yq eval 'select(.kind == "HTTPRoute") | .spec.hostnames[0]'`
- [x] **Создаёт `gitops/workloads/<group>/<app>.yaml`:** один Application с `recurse: true`, depends-on, sync-wave 90
- [x] **Патч gateway listener** (если есть `gateway.yaml`) через `yq eval -i`
- [x] Идемпотентность: listener не дублируется
- [x] `--dry-run`: показать содержимое файлов
- [x] `--sync`: git add + git commit
- [x] `--push`: git push

---

## Phase 5 — `atlasctl disable <group>/<app>` ✓

**Цель:** Убрать workload из GitOps.

- [x] Реализовать `cmd_disable()`:
  - **Порядок:**
    1. Сначала удалить listener из gateway (иначе ArgoCD пересоздаст app)
    2. Потом удалить Application CRs
  - Чтение hostname из `gateway.yaml` (если есть):
    ```bash
    yq -i 'del(.spec.listeners[] | select(.name == "https-'"$APP"'"))' \
      gitops/platform-kind/layers/networking/values/gateway-resources/gateway.yaml
    ```
- [ ] Удаляет:
  - `gitops/workloads/<group>/<app>.yaml`
  - Если папка `<group>/` пуста — удаляет и её
- [ ] Флаги:
  - `--sync`: `git add -A gitops/workloads/<group>/` + `git add gitops/platform-kind/layers/networking/values/gateway-resources/gateway.yaml` + `git commit -m "disable(workloads): remove {{GROUP}}/{{APP}}"`
  - `--push`: `git push`
  - `--dry-run`: показать какие файлы будут удалены
  - `--keep-workload`: не трогать `workloads/<group>/<app>/`
  - `-y`: без подтверждения

---

## Phase 6 — `atlasctl status <group>/<app>` ✓

- [x] Реализовать `cmd_status()`:
  - Поля: name, namespace, features, enabled, gateway-listener, argocd-sync
  - `--json`: вывод в JSON

---

## Phase 7 — `atlasctl list` ✓

- [x] Реализовать `cmd_list()`:
  - Сканирует `workloads/` на наличие `app.yaml`
  - Для каждого: group, app, features, enabled status, gateway listener
  - `--json`: вывод в JSON, цветной вывод (`✓` — enabled, `○` — disabled)

---

## Phase 8 — Интеграция Seal

**Цель:** Перевести Seal на новый workflow.

- [ ] Мигрировать `workloads/aldoshkineg/seal/`:
  - Удалить `database/cluster.yaml`, `database/objectstore.yaml`, `database/scheduled-backup.yaml`, `database/pod-monitor.yaml`
  - Удалить `database/external-secret.yaml`, `s3/external-secret.yaml` (если есть)
  - Создать `secrets.yaml` — один файл DB + S3 + Redis
  - Удалить старый `gitops/workloads/layers/aldoshkineg/` (весь)
  - Создать свежий `app.yaml` по новому шаблону
  - Выполнить `atlasctl enable` для создания `gitops/workloads/aldoshkineg/seal.yaml`
- [ ] `atlasctl seed aldoshkineg/seal` → exit 0:
  - Создана БД `sealdb` в production-db
  - Создан бакет `workloads/aldoshkineg/seal` в MinIO
  - Все credentials записаны в Vault
- [ ] `atlasctl enable aldoshkineg/seal -y --sync --push`:
  - Создан `gitops/workloads/aldoshkineg/seal.yaml`
  - Добавлен listener `https-seal` в gateway.yaml
  - ArgoCD засинкал Application
- [ ] `atlasctl status aldoshkineg/seal` →:
  - `enabled: true`
  - `features: [secrets, monitoring, gateway]`
  - `gateway-listener: true`
- [ ] `atlasctl disable aldoshkineg/seal -y`:
  - Удалён listener `https-seal` из gateway
  - Удалён `seal.yaml` из gitops
- [ ] `atlasctl enable aldoshkineg/seal -y --sync --push` (re-enable):
  - listener восстановлен
  - Application восстановлен
- [ ] `atlasctl list` → показывает `aldoshkineg/seal` с фичами и статусом

---

## Phase 9 — Root-app обновление ✓

- [x] Обновить `gitops/bootstrap/root-app.yaml`:
  - Source 2: `path: gitops/workloads/layers` → `path: gitops/workloads`
  - `exclude: "README.md"` → `exclude: "{README.md,.gitkeep}"`
- [ ] Проверить что root-app синкает Application-ы из `gitops/workloads/` (live cluster test)

---

## Phase 10 — Makefile + Documentation

- [ ] Добавить Makefile targets:
  ```makefile
  atlasctl-new:    tools/atlasctl new $(ARGS)
  atlasctl-seed:   tools/atlasctl seed $(ARGS)
  atlasctl-enable: tools/atlasctl enable $(ARGS)
  atlasctl-disable:tools/atlasctl disable $(ARGS)
  atlasctl-status: tools/atlasctl status $(ARGS)
  atlasctl-list:   tools/atlasctl list $(ARGS)
  ```
- [ ] Обновить `apps/README.md`:
  - Описать полный workflow (new → seed → enable → disable)
  - Описать структуру workload директории
  - Упомянуть `.secret-seed` (gitignored)
  - Убрать упоминание ручного коммита
  - Добавить раздел Infrastructure Components
  - Добавить раздел Argo Rollouts Integration

---

## Phase 11 — Pre-commit & Validation

- [ ] `yamllint` на всех новых YAML файлах
- [ ] `shellcheck` на `tools/atlasctl`
- [ ] `trivy` на шаблонах (не должно быть false positives на `{{}}`)
- [ ] `pre-commit run --all-files` — все хуки проходят
