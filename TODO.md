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

### Infrastructure — fold `zot-image` into Terraform (variant ii) — DONE

`terraform apply` is self-sufficient: the Zot image is imported into Incus by the
`zot_cache` module via `null_resource.import_zot` (`incus image copy` from the ghcr
OCI remote, idempotent — skipped when the `zot-cache` alias is present), with **no**
destroy provisioner so the cache survives `terraform destroy`. The earlier
"download-to-disk + `incus image import --docker`" plan was dropped because incus
7.2 removed the `--docker` flag and because it would have required an extra tool
(skopeo); `incus image copy` uses only the already-required `incus` CLI.

- [x] **zot-cache module: import step** — `null_resource.import_zot` runs
      `incus image copy ghcr-oci:project-zot/zot:v2.1.16 --alias zot-cache`
      (idempotent via `incus image show`), no destroy provisioner.
- [x] **zot-image.sh removed** — image logic lives entirely in HCL; the script and
      the `make zot-image` Makefile target were deleted.
- [x] **Self-contained module** — `incus_instance.zot` depends on `import_zot`; no
      external "image must already exist" prerequisite.
- [x] **Docs** — `make zot-image` removed from Makefile; README, docs/setup.md,
      AGENTS.md, zot-cache/README.md, preflight.sh and stage-terraform-destroy.sh
      updated to state the image is pulled automatically by Terraform.
- [x] **Validate** — `terraform validate`/`fmt` pass; idempotency confirmed (apply
      with alias absent copies once; apply with alias present is a no-op, 0 changes);
      `terraform destroy` does NOT remove the Zot Incus image.
