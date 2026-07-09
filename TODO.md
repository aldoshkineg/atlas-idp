# Atlas IDP — Implementation Roadmap

### Phase 10 — Supply Chain Security & Admission Control

- [ ] **Cosign** — container image signing + verification (только наши образы seal-проекта)
  - [ ] **Key generation** — `cosign generate-key-pair --output-key-prefix security/cosign/cosign`
        (простой key-pair, БЕЗ CA)
    - [ ] Public key committed → `security/cosign/cosign.pub`
    - [ ] Private key (`cosign.key`) → GitHub Secret `COSIGN_PRIVATE_KEY` (raw PEM, never committed)
    - [ ] Use empty passphrase → set `COSIGN_PASSWORD=""` in signing step
    - [ ] `cosign.key` must be gitignored / never staged (`detect-private-key` pre-commit hook)
    - [ ] Document rotation procedure in `security/cosign/README.md`
  - [ ] **Sign in CI** — `.github/workflows/seal-docker-publish.yml`
    - [ ] Add `sigstore/cosign-installer@v3` step (after login, before/after push)
    - [ ] After `docker/build-push-action`, sign **every** pushed tag (matrix × tags)
          loop over `steps.meta.outputs.tags` (newline-separated) with
          `cosign sign --yes --key env://COSIGN_PRIVATE_KEY "$img"`
    - [ ] Sign both `v*` release tags and `workflow_dispatch` dev tags
  - [ ] **Local signing** — extend `apps/seal/Taskfile.yml` `push-images`
    - [ ] Add `sign-images` task (use local `cosign`, read key from env/`$COSIGN_PRIVATE_KEY`)
    - [ ] Keep consistent with CI so local pushes are also verifiable
  - [ ] **Verification helper** — `security/cosign/verify.sh`
    - [ ] `cosign verify --key security/cosign/cosign.pub ghcr.io/aldoshkineg/<svc>:<tag>`
    - [ ] Wire into `make verify` / CI `ci.yaml` as a check (optional)
  - [ ] **Enforcement (admission control)** — see Kyverno `require-image-signature` task below
        (Cosign signs; Kyverno _blocks_ unsigned `ghcr.io/aldoshkineg/*` at deploy time)
  - **Review notes (gaps / risks in original TODO):**
    - [ ] `act-build` / `push-images` push images without signing today → must add local sign path
          or document that only CI pushes are trusted.
    - [ ] Signing must cover all matrix services AND all metadata tags (release + dev) or Kyverno
          will reject legitimately-pushed-but-unsigned tags.
    - [ ] `COSIGN_PRIVATE_KEY` secret must preserve newlines (store raw PEM, not base64, for `env://`).
- [ ] **Kyverno / Policy Controller** — Admission Control
  - [ ] Deploy Kyverno via Argo CD (sync-wave 1)
  - [ ] **Validate: `disallow latest tag`** — block `:latest` image deployments
  - [ ] **Validate: `require-run-as-non-root`** — all pods must set `runAsNonRoot: true`
  - [ ] **Mutate: auto-add security context** — inject `readOnlyRootFilesystem`, `drop: ALL`, `seccomp: RuntimeDefault`
  - [ ] **Validate: `require-labels`** — enforce `app.kubernetes.io/name`, `app.kubernetes.io/instance`
  - [ ] **Validate: `disallow-privileged`** — block `privileged: true` and `hostPath` in workload namespaces
  - [ ] **Validate: `require-image-signature`** — block unsigned images for `ghcr.io/aldoshkineg/*`
  - [ ] **Mutate: auto-add Alloy sidecar** — optionally inject log collector into all pods in `atlasteam-seal`

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
