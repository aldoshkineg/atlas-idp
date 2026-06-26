# atlasctl — Workload Management CLI

Управление жизненным циклом workload-ов в Atlas IDP.

## Установка

```bash
alias atlasctl="$PWD/tools/atlasctl"
```

## Команды

| Команда   | Описание                                                  |
| --------- | --------------------------------------------------------- |
| `new`     | Создать структуру workload                                |
| `seed`    | Провиженинг БД + бакет + запись в Vault                   |
| `enable`  | Включить в GitOps (ArgoCD Application + gateway listener) |
| `disable` | Отключить из GitOps                                       |
| `status`  | Статус workload                                           |
| `list`    | Список всех workloads                                     |

---

## `atlasctl new`

Создаёт `workloads/<group>/<app>/` со всеми манифестами golden path.

```bash
# Минимальный
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git

# С Helm чартом
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git \
  --repo-path charts/myapp --helm

# С Helm values
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp.git \
  --repo-path charts/seal --helm --helm-values ./seal-values.yaml
```

### Флаги

| Флаг                | Описание                                             |
| ------------------- | ---------------------------------------------------- |
| `--group <g>`       | Группа/команда                                       |
| `--repo <url>`      | URL репозитория приложения                           |
| `--namespace <ns>`  | Namespace (по умолч.: `<group>-<app>`)               |
| `--repo-path <p>`   | Путь к манифестам в репо (по умолч.: `.`)            |
| `--helm`            | Использовать Helm                                    |
| `--helm-values <s>` | Inline values или путь к файлу                       |
| `--sa <sas>`        | Service accounts для Vault auth (по умолч.: `<app>`) |
| `-y` / `--yes`      | Без подтверждения                                    |

> Все манифесты генерируются всегда: gateway.yaml (HTTPRoute + Certificate), secrets.yaml (ExternalSecrets), vault/, monitoring/, infra/ (NetworkPolicy + ResourceQuota). Отдельные флаги для каждого типа не требуются.

### Структура после `new`

```
workloads/<group>/<app>/
├── app.yaml               # ArgoCD Application (внешний репо + resources/)
├── .secret-seed            # Сгенерированные пароли DB / S3 / Redis
├── secrets.yaml            # ExternalSecrets: DB + S3 + Redis
├── vault/                  # Vault policy + k8s auth role + seed config
│   ├── policy.hcl
│   ├── k8s-auth-role.yaml
│   └── seed-mapping.conf
├── monitoring/             # PodMonitor + PrometheusRule
│   ├── pod-monitor.yaml
│   └── prometheus-rule.yaml
└── infra/                  # Платформенные ресурсы кластера
    ├── gateway.yaml        #   → gateway-routes/ (enable)
    ├── network-policy.yaml #   → resources/
    └── resource-quota.yaml #   → resources/
```

---

## `atlasctl seed`

Провиженинг PostgreSQL (создание БД + пользователя), MinIO (бакет + ключи), запись credentials в Vault.

```bash
atlasctl seed aldoshkineg/seal
```

Читает `.secret-seed` и `vault/seed-mapping.conf`. Сгенерированные DB/S3/Redis credentials автоматически записываются в `secret/workloads/<group>/<app>/`.

---

## `atlasctl enable`

Создаёт ArgoCD Application CR в `gitops/workloads/<group>/<app>.yaml`, синхронизирует манифесты в `gitops/workloads/<group>/<app>/resources/`, копирует `infra/gateway.yaml` в `gateway-routes/<app>.yaml` и добавляет TLS listener в gateway.

```bash
# Предпросмотр
atlasctl enable aldoshkineg/seal --dry-run

# Включить + commit + push
atlasctl enable aldoshkineg/seal --sync --push
```

---

## `atlasctl disable`

Удаляет gateway listener, ArgoCD Application CR из `gitops/workloads/`, файл из `gateway-routes/` и пустую групповую папку.

```bash
# Предпросмотр
atlasctl disable aldoshkineg/seal --dry-run

# Отключить
atlasctl disable aldoshkineg/seal -y

# Отключить + commit + push
atlasctl disable aldoshkineg/seal -y --sync --push
```

---

## `atlasctl list`

```bash
$ atlasctl list
Workloads:
  aldoshkineg/seal  [secrets gateway monitoring]
```

---

## Full Workflow

```bash
# 1. Scaffold
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp.git \
  --repo-path charts/seal --helm

# 2. Настроить (опционально) — отредактировать файлы, .secret-seed

# 3. Провиженинг инфраструктуры
atlasctl seed aldoshkineg/seal

# 4. Включить в GitOps
atlasctl enable aldoshkineg/seal --dry-run
atlasctl enable aldoshkineg/seal --sync --push

# 5. Статус
atlasctl status aldoshkineg/seal

# 6. Отключить
atlasctl disable aldoshkineg/seal --dry-run   # просмотр
atlasctl disable aldoshkineg/seal -y          # отключить
atlasctl disable aldoshkineg/seal -y --sync --push  # отключить + commit + push
```
