# Atlas IDP — Implementation Roadmap

### Phase 10 — Supply Chain Security & Admission Control

- [ ] **Cosign** — container image signing + verification (только наши образы seal-проекта)
  - [x] **Key generation** — `cosign generate-key-pair --output-key-prefix security/cosign/cosign`
        (простой key-pair, БЕЗ CA)
    - [x] Public key committed → `security/cosign/cosign.pub`
    - [x] Private key (`cosign.key`) → GitHub Secret `COSIGN_PRIVATE_KEY` (raw PEM, never committed)
    - [x] Use empty passphrase → set `COSIGN_PASSWORD=""` in signing step
    - [x] `cosign.key` must be gitignored / never staged (`detect-private-key` pre-commit hook)
    - [ ] Document rotation procedure in `security/cosign/README.md`
  - [x] **Sign in CI** — `.github/workflows/seal-docker-publish.yml`
    - [x] Add `sigstore/cosign-installer@v3` step (after login, before/after push)
    - [x] After `docker/build-push-action`, sign **every** pushed tag (matrix × tags)
          loop over `steps.meta.outputs.tags` (newline-separated) with
          `cosign sign --yes --key env://COSIGN_PRIVATE_KEY "$img"`
    - [x] Sign both `v*` release tags and `workflow_dispatch` dev tags
  - [x] **Local signing** — extend `apps/seal/Taskfile.yml` `push-images`
    - [x] Add `sign-images` task (use local `cosign`, read key from env/`$COSIGN_PRIVATE_KEY`)
    - [x] `push-images` now signs after push; skipped gracefully if key unset
    - [x] Keep consistent with CI so local pushes are also verifiable
  - [x] **Verification helper** — `security/cosign/verify.sh`
    - [x] `cosign verify --key security/cosign/cosign.pub ghcr.io/aldoshkineg/<svc>:<tag>`
    - [x] `make seal-verify TAG=vX.Y.Z` wrapper
  - [x] **Enforcement (admission control)** — Kyverno `require-image-signature` активна в **Audit**
        (Cosign signs; Kyverno верифицирует подпись у `ghcr.io/aldoshkineg/*` на deploy).
        Блокировка (Enforce) пока НЕ включена — см. ниже.
  - **Review notes (gaps / risks in original TODO):**
    - [x] `act-build` / `push-images` push images without signing today → must add local sign path
          (сделано: `sign-images` + `push-images` подписывает после push).
    - [ ] Signing must cover all matrix services AND all metadata tags (release + dev) or Kyverno
          will reject legitimately-pushed-but-unsigned tags.
    - [x] `COSIGN_PRIVATE_KEY` secret must preserve newlines (store raw PEM, not base64, for `env://`).
          (подтверждено рабочим: CI подписывает успешно)
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
