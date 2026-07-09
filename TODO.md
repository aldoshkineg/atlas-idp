# Atlas IDP — Implementation Roadmap

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
