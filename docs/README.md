# Atlas IDP — Documentation

Index of all project documentation. Start with [`setup.md`](setup.md) if you are
bootstrapping the platform, or [`tech-stack.md`](tech-stack.md) for the technology
inventory.

## Getting started

| Doc                                            | Contents                                                     |
| ---------------------------------------------- | ------------------------------------------------------------ |
| [`setup.md`](setup.md)                         | Zero-to-ready: prerequisites, `.env`, bootstrap              |
| [`requirements.md`](requirements.md)           | Pinned tool versions & host sizing (single source of truth)  |
| [`tech-stack.md`](tech-stack.md)               | Every technology used and why it matters                     |
| [`cluster-internals.md`](cluster-internals.md) | How VIPs, eBPF LB and DRBD CSI actually work (verified live) |

## Infrastructure

| Doc                        | Contents                                                       |
| -------------------------- | -------------------------------------------------------------- |
| [`talos.md`](talos.md)     | Talos operational notes, DRBD modules, Incus gotchas           |
| [`incus.md`](incus.md)     | Hypervisor host: networking, snapshots, troubleshooting        |
| [`linstor.md`](linstor.md) | Replicated block storage (LINSTOR/DRBD) on Talos               |
| [`cilium.md`](cilium.md)   | CNI, LoadBalancer (L2), Gateway API                            |
| [`zot.md`](zot.md)         | OCI pull-through registry cache (→ `infra/modules/zot-cache/`) |

## Platform services

| Doc                                    | Contents                                       |
| -------------------------------------- | ---------------------------------------------- |
| [`gitops.md`](gitops.md)               | Argo CD app-of-apps, layers, sync waves        |
| [`vault.md`](vault.md)                 | Vault (Bank-Vaults) + External Secrets flow    |
| [`velero.md`](velero.md)               | Cluster backup/restore (CSI snapshots → MinIO) |
| [`cnpg.md`](cnpg.md)                   | PostgreSQL operator, Barman backups & recovery |
| [`observability.md`](observability.md) | Metrics, logs, traces pipelines                |
| [`scaling.md`](scaling.md)             | KEDA event-driven autoscaling + HPA            |
| [`security.md`](security.md)           | Network policies, Kyverno, Trivy, RBAC         |
| [`ca.md`](ca.md)                       | Private PKI / cert-manager                     |
| [`cosign.md`](cosign.md)               | Image signing & admission verification         |
| [`ci.md`](ci.md)                       | GitHub Actions pipelines, act, quality gates   |

## Developer experience

| Doc                            | Contents                                             |
| ------------------------------ | ---------------------------------------------------- |
| [`workloads.md`](workloads.md) | Golden-path pipeline: templates → workloads → GitOps |
| [`atlasctl.md`](atlasctl.md)   | Platform CLI reference (→ `tools/atlasctl/`)         |
| [`seal.md`](seal.md)           | Reference workload (→ `apps/seal/`)                  |

## Decisions & operations

- [`adr/`](adr/README.md) — Architecture Decision Records (Talos/Incus, Cilium,
  Rollouts, Vault/ESO)
- [`runbooks/`](runbooks/) — operational procedures: cluster health, Argo CD
  debugging & gRPC login, Vault troubleshooting, cert verification, CI debugging

## Conventions

- Component docs follow one structure: **Components → Our configuration → Real
  usage → Known limitations → See also**. Real usage references `make` targets
  backed by e2e tests under `tests/`.
- `atlasctl.md`, `seal.md` and `zot.md` are symlinks to the canonical READMEs next
  to the code (GitHub web UI shows the link target; local tools follow them).
- Versions live in `requirements.md` only; other docs reference, not repeat, them.
