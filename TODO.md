# Atlas IDP — Implementation Roadmap

### Phase 10 — Supply Chain Security & Admission Control

- [x] **Kyverno / Policy Controller** — Admission Control (минимальный набор, Kyverno 1.13.5 / chart 3.3.8)
  - **Версия:** 3.8.1 отброшен — перешёл на CEL-only, **убрал классический `ClusterPolicy` API**.
        Выбран **3.3.8** (Kyverno 1.13.5): классический `ClusterPolicy` ещё есть (legacy, не удалён).
  - **CRD-проблема (решено):** Argo CD / `helm template` **не рендерит subchart-CRD** (`charts/crds`),
        поэтому admission-controller падал (нет `clusterpolicies.kyverno.io`).
        Решение — отдельное приложение `kyverno-crds` (суб-чарт `crds` целиком, standalone с
        завендоренными parent-helper-ами), sync-wave **4**; у чарта `crds.install: false`.
  - [x] Deploy Kyvernо via Argo CD — `gitops/platform/security/kyverno.yaml` (Helm, ns `kyverno`, sync-wave 5)
  - [x] **`require-image-signature`** — verifyImages на `ghcr.io/aldoshkineg/*`, **Audit** (Enforce пока нет).
        В spec дописаны `mutateDigest: false` (в Audit обязательно), `skipBackgroundRequests: true`,
        `useCache: true`, `verifyDigest: true` — иначе Kyverno дописывает их сам → Argo OutOfSync.
  - [x] **`disallow-latest-tag`** — block `:latest`
  - [x] **`require-run-as-non-root`** — `runAsNonRoot: true`
  - [x] **`disallow-privileged`** — block `privileged: true` / `hostPath`
  - [x] **`require-labels`** — `app.kubernetes.io/name`, `app.kubernetes.io/instance`
  - [x] Policies в `gitops/platform/security/kyverno-policies/` (отдельный Argo App, sync-wave 6)
  - [x] Exclude system namespaces (kyverno, argocd, kube-system, monitoring, loki, vault, …) из всех политик
  - [x] **Argo drift fix:** `ignoreDifferences: /spec` на `ClusterPolicy` в `kyverno-policies.yaml`
        (Kyverno мутирует spec политик → без ignoreDifferences вечный OutOfSync).
        `ignoreDifferences` — **top-level `spec.ignoreDifferences`**, НЕ под `syncPolicy`.
  - [x] **clean-reports hook fix:** `policyReportsCleanup.image` → `bitnamilegacy/kubectl:1.33.4`
        (дефолтный `bitnami/kubectl` недоступен офлайн → hook Job в ImagePullBackOff и зависание операции).
  - [ ] Flip `validationFailureAction` Audit→Enforce после наблюдения (стартуем в Audit)
  - **Operational notes (важно):**
    - Родитель `security` стоит на **Manual** — правки манифестов дочерних приложений (напр. `ignoreDifferences`)
          пропагируются только после `argocd app sync security`.
    - При удалении приложений Kyverno: сначала `patch` убрать finalizer
          `resources-finalizer.argocd.argocd.io`, иначе зависание на post-delete hook (тянет `bitnami/kubectl`).
    - _Вне минимума (опц.):_ Mutate auto-add security context; Mutate auto-add Alloy sidecar (atlasteam-seal)

### Phase 11 — Documentation & ADRs

- [ ] **Architecture Decision Records (ADRs)** — `docs/adr/`
  - [ ] ADR-001: Workload onboarding pattern (atlasctl → GitOps → Vault → Gateway)
  - [ ] ADR-002: Secrets strategy (ExternalSecrets vs Vault Agent)
  - [ ] ADR-003: Rollout vs Deployment decision
  - [ ] ADR-004: Observability stack choices (Prom/Loki/Tempo/Alloy)
- [ ] **Platform overview** — `docs/` with architecture diagram, component relationships
- [ ] **Runbooks** — `docs/runbooks/`
  - [ ] Cluster recovery from Velero backup
  - [ ] Canary abort / promote procedures
  - [ ] Vault unseal procedure
- [ ] **Disaster Recovery drill** — document and verify Velero restore end-to-end

---
