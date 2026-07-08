# Atlas IDP — Implementation Roadmap

### Phase 10 — Supply Chain Security & Admission Control

- [ ] **Cosign** — container image signing in CI
  - [ ] `cosign generate-key-pair` → private key in GitHub Secrets, public key in repo
  - [ ] Add `cosign sign --key` to `.github/workflows/seal-docker-publish.yml` after push
  - [ ] Keyless verification for third-party images (Grafana, Loki, etc.)
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
