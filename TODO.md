# Atlas IDP — Implementation Roadmap

Remaining work. Completed phases and the platform overview (now covered by
`README.md`) have been removed.

### Documentation & ADRs

- [ ] **Architecture Decision Records (ADRs)** — `docs/adr/`
  - [ ] ADR-001: Workload onboarding pattern (atlasctl → GitOps → Vault → Gateway)
  - [ ] ADR-002: Secrets strategy (ExternalSecrets vs Vault Agent)
  - [ ] ADR-003: Rollout vs Deployment decision
  - [ ] ADR-004: Observability stack choices (Prom/Loki/Tempo/Alloy)
- [ ] **Runbooks** — `docs/runbooks/`
  - [ ] Cluster recovery from Velero backup
  - [ ] Canary abort / promote procedures
  - [ ] Vault unseal procedure
- [ ] **Disaster Recovery drill** — document and verify Velero restore end-to-end

### Infrastructure — fold `zot-image` into Terraform (variant ii)

Goal: make `terraform apply` self-sufficient (drop the separate `make zot-image`
step) by downloading the Zot image to disk once and importing it into Incus via
a `null_resource`, without a destroy provisioner so the cache survives
`terraform destroy` (revises design A from AGENTS.md).

- [ ] **zot-cache module: download step** — add `null_resource.download_zot` that
      pulls `ghcr.io/project-zot/zot:v2.1.16` once to
      `/var/tmp/atlas/zot_cache/zot.tar` (skopeo `oci-archive` or `docker pull`+`save`),
      skipping if the file already exists (mirror `incus` module `download_image`).
- [ ] **zot-cache module: import step** — add `null_resource.import_zot` (or reuse
      `tools/incus/zot-image.sh`) running `incus image import --docker zot.tar
--alias zot-cache`, idempotent (skip if alias present), with **no** destroy
      provisioner so the image is never removed on `terraform destroy`.
- [ ] **zot-image.sh** — extend to support download-to-disk + import so image logic
      stays in one place outside HCL (keep `ensure` callable by the null_resource).
- [ ] **Self-contained module** — `incus_instance.zot` depends on `import_zot`; drop
      the external "image must already exist" prerequisite.
- [ ] **Docs** — remove `make zot-image` from Makefile Getting Started + README;
      revise AGENTS.md design-A note (download-to-disk + Terraform-triggered import).
- [ ] **Validate** — `terraform validate`/`plan` in stage env; confirm idempotency
      (skip if alias present) and that `terraform destroy` does NOT remove the
      Zot Incus image.
