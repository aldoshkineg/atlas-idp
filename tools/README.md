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

Создаёт `workloads/<group>/<app>/` с файлами по golden path.

```bash
# Минимальный workload (только app.yaml)
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git

# С Helm чартом
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git \
  --repo-path charts/myapp --helm

# Полный набор: secrets + ingress + monitoring
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp-seal.git \
  --repo-path charts/seal --helm --secrets --ingress --monitoring
```

### Флаги

| Флаг                | Описание                                                                   |
| ------------------- | -------------------------------------------------------------------------- |
| `--group <g>`       | Группа/команда                                                             |
| `--repo <url>`      | URL репозитория приложения                                                 |
| `--namespace <ns>`  | Namespace (по умолч.: `<group>-<app>`)                                     |
| `--repo-path <p>`   | Путь к манифестам в репо (по умолч.: `.`)                                  |
| `--helm`            | Использовать Helm                                                          |
| `--helm-values <s>` | Inline values или путь к файлу                                             |
| `--secrets`         | Создать `vault/` + `secrets.yaml` (DB + S3 + Redis) + сгенерировать пароли |
| `--ingress`         | Создать `gateway.yaml` (HTTPRoute + Certificate)                           |
| `--monitoring`      | Создать PodMonitor + PrometheusRule                                        |
| `--sa <sas>`        | Service accounts для Vault auth (по умолч.: `<app>`)                       |
| `-y` / `--yes`      | Без подтверждения                                                          |

### Структура после `new`

```
workloads/<group>/<app>/
├── app.yaml              # ArgoCD Application → внешний репо
├── gateway.yaml          # (--ingress) HTTPRoute + Certificate
├── .secret-seed          # (--secrets) сгенерированные пароли
├── vault/
│   ├── policy.hcl        # (--secrets) Vault policy
│   ├── k8s-auth-role.yaml
│   └── seed-mapping.conf
├── secrets.yaml          # (--secrets) ExternalSecrets: DB + S3 + Redis
├── monitoring/           # (--monitoring) PodMonitor + PrometheusRule
└── infra/
    ├── resource-quota.yaml
    └── network-policy.yaml
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

Создаёт ArgoCD Application CR в `gitops/workloads/<group>/<app>.yaml` и добавляет listener в gateway.

```bash
# Предпросмотр
atlasctl enable aldoshkineg/seal --dry-run

# Включить + commit + push
atlasctl enable aldoshkineg/seal --sync --push
```

---

## `atlasctl disable`

Удаляет gateway listener (первым, иначе ArgoCD пересоздаст app), потом удаляет ArgoCD Application CR и пустую групповую папку.

```bash
# Предпросмотр
atlasctl disable aldoshkineg/seal --dry-run

# Отключить
atlasctl disable aldoshkineg/seal -y

# Отключить + commit + push
atlasctl disable aldoshkineg/seal -y --sync --push

# Не трогать workloads/ директорию
atlasctl disable aldoshkineg/seal -y --keep-workload
```

---

## `atlasctl list`

```bash
$ atlasctl list
Workloads:
  aldoshkineg/seal  [secrets monitoring gateway]
```

---

## Full Workflow

```bash
# 1. Scaffold
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp-seal.git \
  --repo-path charts/seal --helm --secrets --ingress --monitoring

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
