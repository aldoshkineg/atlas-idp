# Documentation

Index of the `docs/` tree. Start with `setup.md` for a fresh cluster, then
`gitops.md` + `workloads.md` for the delivery model.

## Guides

| Doc                | Purpose                                                |
| ------------------ | ------------------------------------------------------ |
| `setup.md`         | Bootstrap the stage (Incus/Talos/Cilium + Vault seeds) |
| `ci.md`            | CI/CD phases (base / middleware / workload)            |
| `gitops.md`        | Argo CD app-of-apps model and platform layers          |
| `workloads.md`     | Workload onboarding pipeline (templates → gitops)      |
| `gitops-review.md` | Review notes / checklist for GitOps manifests          |

## Reference

| Doc                   | Purpose                                  |
| --------------------- | ---------------------------------------- |
| `CA.md`               | Root CA bootstrap and trust distribution |
| `cosign.md`           | Image signing + Kyverno verification     |
| `netpol.md`           | NetworkPolicy model                      |
| `linstor.md`          | LINSTOR storage                          |
| `incus-management.md` | Incus VM lifecycle                       |
| `talos.md`            | Talos cluster ops                        |
| `requirements.md`     | Pinned CLI versions + platform sizing    |

## Architecture Decision Records

See [`adr/README.md`](adr/README.md).

## Runbooks

See [`runbooks/`](runbooks/): cluster health, Vault, cert verification,
Argo CD / CI debugging.
