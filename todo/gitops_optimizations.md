# GitOps Rebuild — оптимизации (после ревью)

Статус: предложения, НЕ внедрено. Решает пользователь.

## Приоритетные (влияют на надёжность подъёма)

- [ ] **1. metrics-server → `base`** — сейчас в `observability` (manual), не поднимается авто.
      Ядро для HPA/автоскейла; на слабой машине логично поднимать с фундаментом.
      Действие: `git mv gitops/platform/observability/metrics-server.yaml gitops/platform/base/metrics-server.yaml` + перенести `observability/values/metrics-server.yaml` → `base/values/`. Риск: нет.
- [ ] **2. `depends-on: vault-operator`** для `platform-secrets` и `external-secrets` (base).
      Гарантирует Vault перед External Secrets / платформенными секретами.
      Действие: добавить аннотацию `argocd.argoproj.io/depends-on: vault-operator`
      в `gitops/platform/base/platform-secrets.yaml` и `gitops/platform/base/external-secrets.yaml`.

## Архитектурные (стиль / масштабирование)

- [ ] **3. ApplicationSet вместо 6 layer-app** — DRY: один list-generator
      (name/path/wave/automated). Минус: условный syncPolicy (base auto, остальные manual)
      усложняет шаблон Go-template. Выгода: новый слой = одна строка.
- [ ] **4. Per-layer AppProjects** — сейчас все компоненты в `platform`, обёртки в `default`.
      Для изоляции/RBAC дать каждому слою свой AppProject + добавить
      `argoproj.io` Application в whitelist проекта. Сейчас работает, но смешение — техдолг.
- [ ] **5. sync-windows** на тяжёлые слои (observability/storage) при ручном подъёме,
      чтобы не планировать ресурсоёмкий sync в часы пик на слабой машине.

## Выполнено по ревью

- [x] `netpol` (security): `depends-on: gateway-resources` (cross-layer ordering).
- [x] AppProject `platform`: описание актуализировано.
- [x] Удалены осиротевшие пустые каталоги в `gitops/platform/layers/`.
- [x] Удалён мёртвый `gitops/bootstrap/argocd/nginx-charts-repo.yaml`.
