# Workloads — Golden Path Implementation

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

---

## Phase 1 — Refactor `atlasctl new` (inner loop only)

**Цель:** `atlasctl new` создаёт только `workloads/<group>/<app>/`, без gitops layers.

- [ ] Убрать создание `gitops/workloads/layers/<group>/` из `cmd_new()`
- [ ] Обновить next steps в выводе `new`:
  ```diff
  - 6. Commit and push to trigger ArgoCD sync
  + 6. Run: atlasctl test <group>/<app>
  + 7. Run: atlasctl enable <group>/<app> [--sync]
  ```
- [ ] Проверить, что `atlasctl new seal --group aldoshkineg --repo ...` не трогает `gitops/`

---

## Phase 2 — `atlasctl test <group>/<app>`

**Цель:** Валидация workload перед enable. Exit code 0 = ready, 1 = ошибка.

- [ ] Реализовать `cmd_test()` с проверками:

  | Проверка | Что проверяем |
  |----------|---------------|
  | Существование | `workloads/<group>/<app>/` существует |
  | app.yaml | Файл существует, валидный YAML, есть `spec.source.repoURL` |
  | infra.yaml | Файл существует, валидный YAML |
  | vault/ (если есть) | `policy.hcl`, `k8s-auth-role.yaml`, `seed-mapping.conf` |
  | database/ (если есть) | `cluster.yaml`, `objectstore.yaml`, `external-secret.yaml` |
  | s3/ (если есть) | `external-secret.yaml` |
  | monitoring/ (если есть) | `pod-monitor.yaml`, `prometheus-rule.yaml` |
  | Gitops conflict | `gitops/workloads/layers/<group>/<app>.yaml` НЕ существует (если не `--force`) |

- [ ] Добавить `--verbose` — выводит все check-ы подробно
- [ ] Добавить `--json` — выводит результат в JSON (для CI)

---

## Phase 3 — `atlasctl enable <group>/<app>`

**Цель:** Промоутить workload из `workloads/` в `gitops/workloads/layers/`.

- [ ] Реализовать `cmd_enable()` с флагами:

  | Флаг | Описание |
  |------|----------|
  | `--sync` | `git add` + `git commit` |
  | `--push` | `git push` (требует `--sync`) |
  | `--dry-run` | Показать что будет создано, без изменений |
  | `--force` | Пропустить `test` |
  | `-y` | Без подтверждения |

- [ ] Создаёт `gitops/workloads/layers/<group>/<app>.yaml`:

  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: <group>-<app>
    namespace: argocd
  spec:
    project: workloads
    source:
      repoURL: https://github.com/aldoshkineg/atlas-idp.git
      targetRevision: main
      path: workloads/<group>/<app>
      directory:
        include: "app.yaml"
    destination:
      server: https://kubernetes.default.svc
      namespace: <namespace>
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
      retry:
        limit: 10
        backoff:
          duration: 5s
          factor: 2
          maxDuration: 3m
  ```

- [ ] Создаёт `gitops/workloads/layers/<group>/<app>-infra.yaml`:

  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: <group>-<app>-infra
    namespace: argocd
    annotations:
      argocd.argoproj.io/sync-wave: "90"
      argocd.argoproj.io/depends-on: cloudnativepg-operator, cloudnativepg-barman-plugin, minio
  spec:
    project: workloads
    source:
      repoURL: https://github.com/aldoshkineg/atlas-idp.git
      targetRevision: main
      path: workloads/<group>/<app>
      directory:
        exclude: "app.yaml"
    destination:
      server: https://kubernetes.default.svc
      namespace: <namespace>
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
      retry:
        limit: 10
        backoff:
          duration: 5s
          factor: 2
          maxDuration: 3m
  ```

- [ ] Идемпотентность: если файлы уже есть и совпадают — "already enabled, no changes"
- [ ] `--dry-run`: показать diff создаваемых файлов
- [ ] `--sync`: `git add gitops/workloads/layers/<group>/` && `git commit -m "enable(workloads): promote <group>/<app> to gitops"`
- [ ] `--push`: `git push`

---

## Phase 4 — `atlasctl disable <group>/<app>`

**Цель:** Убрать workload из GitOps (удалить ArgoCD Application CRs).

- [ ] Реализовать `cmd_disable()` с флагами:

  | Флаг | Описание |
  |------|----------|
  | `--sync` | `git add` + `git commit` |
  | `--push` | `git push` |
  | `--dry-run` | Показать что будет удалено |
  | `--keep-workload` | Не удалять `workloads/<group>/<app>/` |
  | `-y` | Без подтверждения |

- [ ] Удаляет:
  - `gitops/workloads/layers/<group>/<app>.yaml`
  - `gitops/workloads/layers/<group>/<app>-infra.yaml`
  - Если папка `<group>/` пуста — удаляет и её

- [ ] `--dry-run`: показать какие файлы будут удалены
- [ ] `--sync`: `git add -A gitops/workloads/layers/<group>/` && `git commit -m "disable(workloads): remove <group>/<app> from gitops"`
- [ ] `--push`: `git push`

---

## Phase 5 — `atlasctl status <group>/<app>`

**Цель:** Детальный статус workload.

- [ ] Реализовать `cmd_status()`:

  | Поле | Источник |
  |------|----------|
  | name | `<group>/<app>` |
  | namespace | Из `infra.yaml` или `<group>-<app>` |
  | repoURL | Из `app.yaml` |
  | features | По наличию директорий (secrets, db, s3, monitoring) |
  | enabled | Есть ли `gitops/workloads/layers/<group>/<app>.yaml` |
  | infra-synced | Есть ли `gitops/workloads/layers/<group>/<app>-infra.yaml` |
  | app-synced | Есть ли `gitops/workloads/layers/<group>/<app>.yaml` |
  | argocd-sync | Если `argocd` CLI доступен — статус синка приложения |

- [ ] Цветной вывод: enabled = green, disabled = yellow, error = red

---

## Phase 6 — Интеграция Seal

**Цель:** Проверить, что существующий Seal проходит новый workflow.

- [ ] `atlasctl test aldoshkineg/seal` → exit 0 (все check-ы проходят)
- [ ] `atlasctl status aldoshkineg/seal` → enabled (gitops файлы уже существуют)
- [ ] `atlasctl enable aldoshkineg/seal` → "already enabled, no changes" (идемпотентность)
- [ ] `atlasctl enable aldoshkineg/seal --dry-run` → показывает что файлы уже есть
- [ ] `atlasctl disable aldoshkineg/seal --dry-run` → показывает какие файлы будут удалены
- [ ] `atlasctl disable aldoshkineg/seal -y` → удаляет gitops layers
- [ ] `atlasctl enable aldoshkineg/seal -y` → создаёт gitops layers заново
- [ ] `atlasctl list` показывает aldoshkineg/seal с фичами [secrets db s3 monitoring]

---

## Phase 7 — Makefile + Documentation

**Цель:** Обновить Makefile и README.

- [ ] Добавить Makefile targets:

  ```makefile
  atlasctl-test:
  	tools/atlasctl test $(ARGS)

  atlasctl-enable:
  	tools/atlasctl enable $(ARGS)

  atlasctl-disable:
  	tools/atlasctl disable $(ARGS)

  atlasctl-status:
  	tools/atlasctl status $(ARGS)
  ```

- [ ] Обновить help-секцию в Makefile

- [ ] Обновить `apps/README.md`:
  - Описать полный workflow: `new → test → enable [--sync]` / `disable [--sync]`
  - Убрать упоминание ручного коммита (заменить на `atlasctl enable --sync`)

---

## Phase 8 — Pre-commit & Validation

- [ ] `yamllint` на всех новых YAML файлах
- [ ] `shellcheck` на `tools/atlasctl`
- [ ] `trivy` на шаблонах (не должно быть false positives на `{{}}`)
- [ ] `pre-commit run --all-files` — все хуки проходят