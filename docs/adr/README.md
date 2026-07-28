# Architecture Decision Records

Decision logs for the Atlas IDP. Each ADR records context, decision, and
consequences. New ADRs use the naming `ADR-NNN-kebab-case.md`.

| ADR                                                                                  | Topic                                                           |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| [`ADR-001-talos-incus.md`](ADR-001-talos-incus.md)                                   | Talos Linux on Incus VMs as the cluster foundation              |
| [`ADR-002-cilium-dataplane.md`](ADR-002-cilium-dataplane.md)                         | Cilium as the single dataplane (CNI, LB, Gateway API)           |
| [`ADR-003-argo-rollouts-managed-routes.md`](ADR-003-argo-rollouts-managed-routes.md) | Progressive delivery: Argo Rollouts + Gateway API managedRoutes |
| [`ADR-004-vault-eso.md`](ADR-004-vault-eso.md)                                       | In-cluster Vault (Bank-Vaults) + External Secrets Operator      |
