# CI процесс Atlas IDP

Описание того, как устроена непрерывная интеграция в репозитории: какие
workflow'ы существуют, как они триггерятся, из чего собираются и как их
запускать локально / через self-hosted раннер.

## Обзор компонентов

| Файл                                        | Назначение                                                                               |
| ------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `.github/workflows/ci-all.yaml`             | Оркестратор. Собирает фазы в одну цепочку.                                               |
| `.github/workflows/ci-base.yaml`            | Фаза **base**: `terraform apply` (Incus/Talos) + seed Vault.                             |
| `.github/workflows/ci-middleware.yaml`      | Фаза **middleware**: синк платформенных слоёв (storage/security/delivery/observability). |
| `.github/workflows/ci-workload.yaml`        | Фаза **workload**: seed + синк workload-слоя (seal).                                     |
| `.github/workflows/ci-destroy.yaml`         | Уничтожение инфры (требует `confirm: "destroy"`).                                        |
| `.github/workflows/ci-destroy-force.yaml`   | Полный teardown (Incus/Talos + TF state).                                                |
| `.github/workflows/security.yaml`           | Trivy-скан всего репо (IaC/CVE/секреты).                                                 |
| `.github/workflows/seal-docker-publish.yml` | Сборка/пуш/подпись seal-образов (по тегу `v*`).                                          |
| `.github/workflows/atlasctl-release.yml`    | Релиз `atlasctl` (по тегу `v*`).                                                         |

### Composite-actions (переиспользуемые шаги)

| Action                        | Что делает                                                                                                                                               |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/actions/load-env`    | Реплей секрета `ENV_FILE` в `.env` + экспорт в `$GITHUB_ENV` (с маской). Опц. materialise CA (`materialise_ca`) и derive cosign-ключа (`derive_cosign`). |
| `.github/actions/cluster-env` | Прописывает `KUBECONFIG` и `TF_PLUGIN_CACHE_DIR` в `$GITHUB_ENV`.                                                                                        |
| `.github/actions/tools`       | Устанавливает выбранные CLI через `tools/ci/install-tools.sh` (`VERSION_MAP`).                                                                           |
| `.github/actions/terraform`   | `init` → `plan` → `apply` + проверка нод + CA-секрет для cert-manager.                                                                                   |
| `.github/actions/lint`        | `terraform fmt -check`, `terraform validate`, `yamllint`.                                                                                                |
| `.github/actions/scan`        | `trivy fs` (vuln/secret/misconfig).                                                                                                                      |
| `.github/actions/seed-vault`  | Порт-форвард Vault + `seed-vault.sh`.                                                                                                                    |

### Скрипты (`tools/ci/`)

- `install-tools.sh` — единый источник версий тулчейна (`VERSION_MAP`), включая `jq`.
- `terraform-init.sh` — `terraform init` с retry.
- `sync-layers.sh` — синк ArgoCD-слоёв; парсит `argocd app get -o json | jq`; содержит **health-gate** (падет, если слой не `Synced/Healthy`).
- `seed-gh.sh` — выгружает `.env` в секрет `ENV_FILE`.
- `stage-terraform-destroy.sh` — force-teardown.

## Триггеры

| Событие                         | Что запускается                                                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `push` в `main`                 | `ci-all` → полный пайплайн (lint → base → middleware → workload). Если коммит содержит `[base]` / `[middleware]` / `[workloads]` — **только** эти фазы. |
| `pull_request` в `main`         | `ci-all` → **только lint** (без мутации кластера).                                                                                                      |
| `workflow_dispatch`             | `ci-all` → фазы управляются тумблерами `run_base` / `run_middleware` / `run_workloads` (все `true` по умолчанию).                                       |
| тег `v*`                        | `seal-docker-publish` + `atlasctl-release` (сборка/публикация/подпись).                                                                                 |
| `push`/`PR` в `main` (security) | `security` — Trivy-скан.                                                                                                                                |

Destroy-воркфлоу (`ci-destroy`, `ci-destroy-force`) **не** триггерятся автоматически — только вручную (`workflow_dispatch`), причём `ci-destroy` требует `confirm: "destroy"`.

## Оркестратор `ci-all`

```
gate ──▶ lint ──▶ base ──▶ middleware ──▶ workloads
```

- **`gate`** (ubuntu-latest) — дешёвый шаг. Парсит сообщение коммита и
  выставляет `sel_base` / `sel_middleware` / `sel_workloads`:
  - нет токенов `[base]`/`[middleware]`/`[workloads]` → все `true` (полный пайплайн);
  - есть токен(ы) → `true` только для совпавших фаз.
- **`lint`** крутится на self-hosted раннере (переиспользует кэш тулчейна) и
  является воротами: если fmt/validate/yamllint падают, дальше apply не идёт.
- **Фазы** — вызовы reusable-воркфлоу (`uses:`). Каждая наследует
  `concurrency: atlas-stage`, поэтому две мутирующие фазы никогда не идут
  одновременно (destroy не пересекается с apply).
- **`workflow_dispatch`** для фаз игнорирует селектор из коммита и смотрит на
  тумблеры `run_*`.

> ⚠️ Селектор срабатывает на **любое** вхождение токена в текст коммита. Если в
> сообщении случайно окажется `[base]` (напр. «refactor [base] module»), запустится
> только base-фаза.

### Почему `pull_request` только lint

Применять `terraform apply` на общий stage-кластер из PR опасно и бессмысленно.
PR служит для валидации (fmt/validate/yamllint) до merge, без мутации инфраструктуры.

## Секреты

Единственный репо-секрет, нужный мутирующим воркфлоу — **`ENV_FILE`**. Это
целиком содержимое локального `.env` (Vault-сиды, CA cert/key, cosign-ключ,
токены). Он выгружается одной командой и реплеится внутри раннера:

```bash
make seed-gh   # -> ./security/vault/seed-gh.sh (читает .env, грузит в ENV_FILE)
```

Внутри CI `load-env` пишет `.env`, экспортирует каждую переменную в
`$GITHUB_ENV` с `::add-mask::` (маскировка в логах) и опционально материализует
CA. После `ci-base` рабочая копия очищается (`rm -f .env security/certs/*`) при
`if: always()`, чтобы секреты не оставались на persistent self-hosted раннере.

> cosign-ключ в `ENV_FILE` имеет пустой пароль (`COSIGN_PASSWORD: ""` в
> `seal-docker-publish.yml`) — подпись фактически не защищена паролем. План:
> перейти на keyless (Fulcio/OIDC) или задать реальный пароль.

## Локальный запуск vs cloud self-hosted раннер

GitHub-воркфлоу используют **reusable-вызовы** (`uses:`), которые `act`
(локальный эмулятор) не умеет исполнять. Поэтому локально фазы гоняются
напрямую через `tools/ci/act-runner/act-runner.sh`, а не через `ci-all`:

```bash
make act-ci            # base -> middleware -> workload (последовательно, через act)
make act-stage-base    # только base
make act-destroy       # ci-destroy через act
```

Для реального прогона в GitHub используется **self-hosted раннер**
(`myoung34/github-runner`, метка `self-hosted`), поднятый через
`tools/ci/local-runner`:

```bash
make ci-runner-up      # поднять раннер (Docker + Incus + /var/tmp/atlas)
make ci-runner-ci      # dispatch ci-all в GitHub (через раннер)
make ci-runner-down    # остановить
```

Раннер должен иметь доступ к Docker-сокету, Incus-сокету и `/var/tmp/atlas`
(там kubeconfig/талос-артефакты и кэш).

## Полезные Make-цели

| Цель                                                          | Действие                                           |
| ------------------------------------------------------------- | -------------------------------------------------- |
| `make act-ci`                                                 | Полный пайплайн локально (act).                    |
| `make ci-runner-ci`                                           | Полный пайплайн в GitHub через self-hosted раннер. |
| `make seed-gh`                                                | Загрузить `.env` в секрет `ENV_FILE`.              |
| `make validate`                                               | terraform fmt/validate + yamllint + trivy.         |
| `make pre-commit`                                             | Pre-commit хуки.                                   |
| `make ci-runner-{base,middle,workload,destroy,destroy-force}` | Отдельные фазы через раннер.                       |

## Заметки по безопасности / best practices

- Least-privilege `permissions` (в мутирующих воркфлоу `{}` + per-job `contents: read`).
- `security` имеет собственную `concurrency` (`security-<ref>`) и не блокирует прогон инфры.
- `actions/checkout` везде с `persist-credentials: false`; во всех шагах `set -euo pipefail`.
- Все third-party экшены запинены по тегу (`@v4`, `@v3` …) — кандидат на SHA-пининг + Dependabot.
- `sync-layers.sh` имеет health-gate: зелёный CI теперь означает, что слои реально `Synced/Healthy`.
