# GitOps Rebuild — разбиение на слои (app-of-apps)

Статус: **в работе**. Бэкап текущего состояния: `gitops.bak/` (не коммитится, `.gitignore`).

## Зачем

На слабой машине нет ресурсов поднять всё сразу. Нужен инкрементальный
подъём: `base` стартует автоматически, остальные слои — по требованию
одной командой `argocd sync <layer>`.

## Решения (зафиксированы)

- Слой = отдельный Argo CD `Application` = отдельный каталог. Без вложенных
  промежуточных подкаталогов (`foundation/cert-manager/` и т.п. — плоско).
- `foundation` переименован в **`base`**.
- `recurse: false` у слоёв → `values/` и `resources/` игнорируются родителем,
  `exclude` не нужен. `recurse: true` остаётся только у `workloads`.
- Имена дочерних приложений сохраняются (keda, cert-manager…) → Argo
  обновляет на месте, без удаления/пересоздания.
- Cross-layer ordering закрывается `depends-on` на уровне компонентов,
  не sync-wave слоёв.

## Маппинг компонентов

| Слой            | Sync   | wave | Компоненты (откуда взято)                                                                                                                                                       |
| --------------- | ------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `base`          | AUTO   | -100 | gateway-\*, loadbalancer, restart-cilium (networking); cert-manager, cert-manager-issuers, external-secrets, platform-secrets, vault-operator, vault-secrets-webhook (security) |
| `storage`       | manual | -50  | cnpg-_, postgres-cluster, redis (data); linstor-_, minio, snapshot-\*, velero (storage)                                                                                         |
| `security`      | manual | 0    | netpol (networking); trivy-operator; kyverno (позже)                                                                                                                            |
| `observability` | manual | 10   | metrics-server (base); alloy, loki, prom-stack, tempo (observability)                                                                                                           |
| `delivery`      | manual | 20   | keda, argo-rollouts-\* (base)                                                                                                                                                   |
| `workloads`     | manual | 50   | gitops/workloads (без изменений)                                                                                                                                                |

## План / чек-лист

- [x] Бэкап `gitops.bak/`, добавлен в `.gitignore`
- [x] Перенос компонентов в `gitops/platform/<layer>/` (git mv)
- [x] Переписать внутренние пути `gitops/platform/layers/<X>/` → `gitops/platform/<layer>/`
- [x] Обновить `app.kubernetes.io/layer` метки
- [x] Создать 6 layer-application манифестов в `gitops/platform/layers/`
- [x] Переписать `root-app.yaml` (recurse:false, только children)
- [x] Перенести `platform.yaml` (AppProject) в `gitops/platform/layers/`
- [x] Обновить внешние ссылки: atlasctl (go/yaml/sh/tests), `.pre-commit-config.yaml`, `infra/environments/stage/main.tf`
- [x] Обновить документацию (AGENTS.md, netpol.md, linstor.md, ADR-005, ai/trace)
- [x] Проверка: `go build/test` atlasctl (OK), `yamllint` (только pre-existing warning в seal-дашборде), grep старых путей (чисто)
- [ ] Подъём на кластере: `argocd sync base`, затем по одному `argocd sync <layer>`

## Ревью (2026-07-08)

### Что проверено и корректно

- `root-app` → `recurse: false` на `gitops/platform/layers`; создаёт ровно 6 layer-app + AppProject `platform`.
- Каждый слой — отдельный `Application`, `recurse: false` → `values/` и `resources/` игнорируются родителем, `exclude` не нужен.
- `base` = AUTO (`prune`+`selfHeal`, wave `-100`); остальные manual. `workloads` оставлен `recurse: true`+`exclude`.
- Имена дочерних приложений сохранены → Argo обновит на месте без пересоздания.
- AppProject `platform` вынесен в `gitops/platform/layers/` с wave `-1000` (создаётся до слоёв).
- Внешние ссылки (atlasctl go/sh/yaml/tests, .pre-commit, stage/main.tf, docs) обновлены; старых путей нет.
- `go build/test` atlasctl — OK; `yamllint` — только pre-existing warning на seal-дашборде.

### Внесённые правки по ревью

- [x] `netpol` (security): добавлен `depends-on: gateway-resources` — гарантирует Gateway перед сетевыми политиками (cross-layer ordering).
- [x] AppProject `platform`: описание актуализировано под новые слои.
- [x] Gateway-манifestы (Gateway/GatewayClass/HTTPRoute, 8 файлов) перенесены из `base/values/gateway-*` в `base/resources/gateway-*` (соблюдение конвенции: values=helm, resources=k8s). Обновлены `source.path` в `gateway-resources.yaml`/`gateway-routes.yaml` и все ссылки в `atlasctl` (go/sh/yaml/tests). `go build/test` atlasctl — OK.

### Предложения по оптимизации (НЕ внедрено — на решение)

1. **metrics-server в base** — сейчас в `observability` (manual), поэтому не поднимается с `base`. Это ядро для HPA/автоскейла; на слабой машине имеет смысл поднять автоматически. Вариант: перенести `metrics-server.yaml` в `base` (авто). Риск: нет.
2. **depends-on для vault-зависимых в base** — `platform-secrets`/`external-secrets` не имеют `depends-on: vault-operator`. Внутри base волны это обычно перекрывают, но для гарантии стоит добавить.
3. **DRY через ApplicationSet** — 6 почти одинаковых layer-app можно заменить одним `ApplicationSet` (list generator: name/path/wave/automated). Минус: условный syncPolicy (base auto, остальные manual) усложняет шаблон. Выгода: новый слой = одна строка.
4. **Per-layer AppProjects** — сейчас все компоненты в одном проекте `platform`, а обёртки слоёв — в `default`. Для настоящей изоляции/RBAC можно дать каждому слою свой AppProject (и добавить `argoproj.io` Application в whitelist `platform`). Сейчас работает, но смешение проектов — техдолг.
5. **`argocd app sync --direction` / sync-windows** — при ручном подъёме слоёв на слабой машине можно добавить sync-windows на ресурсоёмкие слои (observability/storage), чтобы не планировать тяжёлый sync в часы пик.

## Порядок подъёма на кластере (слабая машина)

1. `argocd sync base` — gateway, cert-manager, vault, ES (фундамент)
2. `argocd sync storage` — когда нужны БД/объектное хранилище
3. `argocd sync security` — сетевые политики, trivy
4. `argocd sync observability` — метрики/логи/трейсы
5. `argocd sync delivery` — keda, argo-rollouts
6. `argocd sync workloads` — пользовательские приложения

## Откат

Полностью: `rm -rf gitops && mv gitops.bak gitops`. Частично: вернуть файл из
`gitops.bak/` через `git checkout` или `cp`.
