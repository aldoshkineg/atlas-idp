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
  - [ ] **Enforcement (admission control)** — see Kyverno `require-image-signature` task below
        (Cosign signs; Kyverno _blocks_ unsigned `ghcr.io/aldoshkineg/*` at deploy time)
  - **Review notes (gaps / risks in original TODO):**
    - [ ] `act-build` / `push-images` push images without signing today → must add local sign path
          or document that only CI pushes are trusted.
    - [ ] Signing must cover all matrix services AND all metadata tags (release + dev) or Kyverno
          will reject legitimately-pushed-but-unsigned tags.
    - [ ] `COSIGN_PRIVATE_KEY` secret must preserve newlines (store raw PEM, not base64, for `env://`).
- [x] **Kyverno / Policy Controller** — Admission Control (минимальный набор, Kyverno 1.13.5 / chart 3.3.8; 3.8.1 отброшен — убрали классический ClusterPolicy API)
  - [x] Deploy Kyverno via Argo CD — `gitops/platform/security/kyverno.yaml` (Helm, ns `kyverno`, sync-wave 5)
  - [x] **Validate: `require-image-signature`** — block unsigned `ghcr.io/aldoshkineg/*` (verifyImages, Audit→Enforce)
  - [x] **Validate: `disallow latest tag`** — block `:latest` image deployments
  - [x] **Validate: `require-run-as-non-root`** — all pods must set `runAsNonRoot: true`
  - [x] **Validate: `disallow-privileged`** — block `privileged: true` and `hostPath` in workload namespaces
  - [x] **Validate: `require-labels`** — enforce `app.kubernetes.io/name`, `app.kubernetes.io/instance`
  - [x] Put policies in `gitops/platform/security/kyverno-policies/` (separate Argo App, sync-wave 6)
  - [x] Exclude system namespaces (kyverno, argocd, kube-system, monitoring, loki, vault, …) from all policies
  - [ ] Flip `validationFailureAction` Audit→Enforce after observing (начинаем в Audit)
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
