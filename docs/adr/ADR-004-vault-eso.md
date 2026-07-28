# ADR-004: In-cluster Vault (Bank-Vaults) + External Secrets Operator

**Status:** Accepted
**Date:** 2026-07
**Supersedes:** the original ADR-005 (ESO against an external Vault server),
which no longer matched the implementation and was removed.

## Context

No secret may live in git, but platform components (MinIO, Redis, Grafana,
Velero, CNPG) all expect ordinary Kubernetes Secrets (`existingSecret`). An
earlier design pointed ESO at an external Vault server; that coupled the
cluster to an out-of-scope dependency and was replaced by a fully in-cluster,
GitOps-managed stack.

## Decision

Run **HashiCorp Vault in-cluster via the Bank-Vaults operator**, and project
secrets into Kubernetes with **External Secrets Operator (ESO)**:

- **Bank-Vaults operator** (1.24.0) manages a `Vault` CR
  (`gitops/platform/base/resources/vault/vault-cr.yaml`): single replica,
  `file` storage on a `linstor-replicated` PVC (block-level DRBD replication),
  TLS terminated at the Cilium Gateway (`vault.atlas`), **auto-unseal** from the
  `vault-unseal-keys` Secret, and — decisively — `externalConfig` as code:
  Kubernetes auth, policies and the KV v2 engine are declared in the CR, not
  scripted post-install.
- **ESO** (0.14.0): one `ClusterSecretStore` → `http://vault.vault.svc:8200`;
  `ExternalSecret`s render platform Secrets (refresh 1m) that charts consume via
  `existingSecret`.
- **Seeding** is a one-way idempotent push: git-ignored `.env` →
  `tools/vault/seed-*.sh` (locally or the CI `seed-vault` action) → Vault KV
  `secret/platform/*`; workload secrets via `atlasctl seed` under
  `secret/workloads/<group>/<app>/`.

## Alternatives considered

- **External Vault server (the superseded ADR)** — rejected: out-of-cluster
  dependency, not reproducible from `make act-ci`.
- **Official `vault-helm` chart** — rejected: init/unseal and all auth/policy
  configuration would need custom automation; Bank-Vaults delivers both
  declaratively.
- **Sealed-Secrets / SOPS** — rejected: encrypted-secrets-in-git has no central
  store, no rotation path, no Kubernetes auth; Vault gives a real
  secret-operating model.
- **Vault Agent injection (bank-vaults webhook) as the primary path** — not
  adopted for delivery: ESO-produced Secrets work with every chart's
  `existingSecret` without sidecars. The webhook is deployed and exercised only
  by `make test-vault` (agent-inject test).

## Consequences

- Zero secrets in git; the entire flow is reproducible and verified end-to-end
  (`make test-vault`: k8s auth → policy → KV read → template render).
- Not Vault-HA: one replica, `file` backend; DRBD protects the data, not
  availability. Acceptable for the lab; HA storage backend is the upgrade path.
- ESO currently authenticates with the **root token** from `vault-unseal-keys`
  — pending hardening to a scoped token bound to `platform-read`.
- First boot requires a one-time manual init/unseal before seeding
  (`docs/setup.md`, `runbooks/vault-troubleshooting.md`).
- The largely unused `vault-secrets-webhook` is kept as an optional injection
  path; dropping it is a candidate cleanup.
