# Cosign — подпись и верификация образов

Страница описывает, как в Atlas IDP подписываются и проверяются
container-образы проекта Seal (`ghcr.io/aldoshkineg/seal-api`,
`ghcr.io/aldoshkineg/seal-worker`, `ghcr.io/aldoshkineg/seal-ui`).

Используется **простой key-pair** (без CA и без keyless/OIDC). Подписываем
только наши образы; third-party образы (Grafana, Loki и т.п.) не проверяются.

## Обзор

| Артефакт          | Где                                 | Статус    |
| ----------------- | ----------------------------------- | --------- |
| `cosign.pub`      | `security/cosign/cosign.pub` (репо) | публичный |
| `cosign.key`      | GitHub Secrets `COSIGN_PRIVATE_KEY` | приватный |
| `COSIGN_PASSWORD` | пустой (ключ без passphrase)        | —         |

Поток:

```
dev → push image → CI cosign sign --key env://COSIGN_PRIVATE_KEY
                                   │
                                   ▼
                            GHCR (image + signature)
                                   │
              verify: cosign verify --key cosign.pub  (локально/CI)
              enforce: Kyverno require-image-signature (в кластере, см. Phase 10)
```

## Генерация ключей

Ключи уже сгенерированы и разложены (см. ниже). Для повторной генерации:

```sh
cosign generate-key-pair --output-key-prefix security/cosign/cosign
# ввод пароля оставить пустым (дважды Enter)
```

Создаёт:

- `security/cosign/cosign.key` — приватный ключ (**не коммитится**, в `.gitignore`)
- `security/cosign/cosign.pub` — публичный ключ (коммитится)

Приватный ключ загружается в GitHub Secrets:

```sh
gh secret set COSIGN_PRIVATE_KEY < security/cosign/cosign.key
```

> Секрет должен содержать **сырой PEM** (с `\n`), не base64 — cosign читает
> его через `env://COSIGN_PRIVATE_KEY`.

## Подпись в CI

`.github/workflows/seal-docker-publish.yml` собирает и пушит образы в матрице
по сервисам (`seal-api`, `seal-worker`, `seal-ui`) и тегам. После шага
`docker/build-push-action` добавляется:

```yaml
- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Sign image
  env:
    COSIGN_PASSWORD: ""
    COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
  run: |
    for img in $(echo "${{ steps.meta.outputs.tags }}" | tr '\n' ' '); do
      cosign sign --yes --key env://COSIGN_PRIVATE_KEY "$img"
    done
```

Подписываются **все** теги, выданные `docker/metadata-action`
(`type=ref,event=tag` для `v*`, а также dev-тег при `workflow_dispatch`).

Локальный путь (Taskfile, опц.): `apps/seal/Taskfile.yml` —
задача `sign-images`, читающая `$COSIGN_PRIVATE_KEY`, вызывается после
`push-images`.

## Верификация

```sh
cosign verify --key security/cosign/cosign.pub \
  ghcr.io/aldoshkineg/seal-api:v0.25.0
```

Успешная верификация возвращает JSON с подписями и код выхода 0.
Можно добавить в `make verify` / шаг CI (`ci.yaml`) как опциональную проверку.

Пример helper-скрипта `security/cosign/verify.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail
KEY="${KEY:-security/cosign/cosign.pub}"
for svc in seal-api seal-worker seal-ui; do
  cosign verify --key "$KEY" "ghcr.io/aldoshkineg/${svc}:${1:?tag required}"
done
```

## Enforcement (admission control)

Блокировка неподписанных образов выполняется Kyverno на стороне кластера
(задача `require-image-signature` в Phase 10), а не самим cosign.
Cosign только **подписывает** и **верифицирует**; Kyverno **запрещает**
деплой `ghcr.io/aldoshkineg/*` без валидной подписи. Для политики Kyverno
нужен публичный ключ — его можно положить в ConfigMap/cluster как
`security/cosign/cosign.pub`.

## Ротация ключей

1. Сгенерировать новую пару: `cosign generate-key-pair --output-key-prefix security/cosign/cosign`
   (предварительно переименовать/архивировать старые файлы).
2. Обновить GitHub Secret `COSIGN_PRIVATE_KEY` новым `cosign.key`.
3. Закоммитить новый `cosign.pub`.
4. Старые подписи остаются валидны, пока образы не переподписаны новым ключом.
   Скоординировать ротацию с политикой Kyverno до удаления старого ключа из
   доверенного набора.

## Устранение неполадок

- **`error: no matching signatures`** — образ не подписан или подписан другим
  ключом. Проверить, что CI отработал шаг `cosign sign` и тег совпадает.
- **`error: key not found` / empty key** — `COSIGN_PRIVATE_KEY` не задан в
  секретах репозитория либо содержит base64 вместо сырого PEM.
- **pre-commit `detect-private-key` ругается** — `cosign.key` попал в индекс;
  убедиться, что он в `.gitignore` (`security/cosign/cosign.key`).
- **подпись не проходит в Kyverno** — проверить, что публичный ключ в политике
  совпадает с `cosign.pub`, и что тег образа точно совпадает с подписанным.
