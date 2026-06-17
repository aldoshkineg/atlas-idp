# Act Runner — Custom Docker Image for Local CI

Кастомный `act` runner image с предустановленными инструментами и persistent bind mount кэшем.

## Состав образа

| Инструмент | Версия |
| ---------- | ------ |
| terraform  | 1.15.3 |
| kubectl    | 1.34.0 |
| kind       | 0.29.0 |
| trivy      | 0.70.0 |
| yamllint   | 1.35.1 |

Версии синхронизированы с `.github/actions/tools/action.yml`.

## Быстрый старт

```bash
# 1. Собрать образ
make act-build

# 2. Запустить CI через act
make act-ci
```

## Структура

```
act-runner/
├── Dockerfile        # Image definition
├── .dockerignore
├── README.md
└── cache/
    ├── tf/           → монтируется в /opt/terraform/plugin-cache
    └── home/         → монтируется в /root/.cache
```

## Кэширование

Bind mount в локальную папку `cache/` позволяет избежать повторной загрузки:

- **Terraform провайдеры** — в `cache/tf/` (TF_PLUGIN_CACHE_DIR)
- **Trivy DB**, pip кэш и др. — в `cache/home/` (~/.cache)

Для полной очистки кэша:

```bash
rm -rf clusters/kind/ci/act-runner/cache/tf/* clusters/kind/ci/act-runner/cache/home/*
```

## Сборка образа

```bash
docker build -t act-runner:latest clusters/kind/ci/act-runner/
```

Или через make:

```bash
make act-build
```

## Переменные и секреты

- `.env` — переменные окружения (AWS_REGION и т.п.)
- `.secrets` — секреты (B2_KEY_ID, B2_APPLICATION_KEY, GITHUB_TOKEN, CA сертификаты)

Секреты из `.secrets` передаются флагом `--secret-file`. CA сертификаты требуют передачи через `-s` из-за multiline формата.

## Запуск вручную

```bash
act -W .github/workflows/ci.yaml \
  -s DEV_CA_CRT="$(cat clusters/kind/certs/ca.crt)" \
  -s DEV_CA_KEY="$(cat clusters/kind/certs/ca.key)"
```

Или через make:

```bash
make act-ci
```
