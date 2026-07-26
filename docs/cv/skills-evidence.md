# Skills → Evidence Map

> For technical interviews: each senior Platform Engineer competency mapped to
> concrete proof in this repository. Use it to navigate straight to the
> evidence when questioned.

| #   | Competency                            | What it proves                                               | Evidence in repo                                                                                                        |
| --- | ------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | **IaC maturity (Terraform/OpenTofu)** | Modular, environment-scoped, version-pinned modules          | `infra/modules/` (talos-config, talos-cluster, incus, cilium, zot-cache, argocd-bootstrap); `versions.tf` per module    |
| 2   | **GitOps operating model**            | App-of-apps, single source of truth, deterministic bootstrap | `gitops/bootstrap/root-app.yaml`; `gitops/platform/layers/*.yaml`; `argocd.argoproj.io/depends-on` ordering             |
| 3   | **Kubernetes ops (CKA-level)**        | Bare-metal cluster build/upgrade, immutable OS               | `infra/modules/talos-config/main.tf`; Talos `vip` control-plane HA; live 3-node cluster                                 |
| 4   | **eBPF networking**                   | One dataplane: CNI + LB + GW + netpols                       | `infra/modules/cilium`; `enable-lb-ipam`, `kube-proxy-replacement`, Gateway API, `CiliumNetworkPolicy`                  |
| 5   | **Zero-trust network**                | Per-workload L3-L7 policy, not just ingress                  | `workloads/atlasteam/seal/infra/ingress-network-policy.yaml`, `ccnp-ingress.yaml` (Cilium CCNP)                         |
| 6   | **HA storage on bare metal**          | Replicated block storage, no cloud volumes                   | `gitops/platform/base/linstor-*.yaml`; StorageClass `linstor-replicated` `autoPlace=2`; LVM-thin + snapshots            |
| 7   | **Secrets management**                | Enterprise secret model, nothing committed                   | `tools/vault/` (policies, K8s auth, bootstrap); `external-secrets` + `gitops/platform/base/external-secrets.yaml`       |
| 8   | **Observability & SRE**               | Metrics/logs/traces triad + alerting                         | `gitops/platform/observability/` (prom-stack, loki, tempo, alloy); custom alert rules; SLO dashboards                   |
| 9   | **Security baseline**                 | Shift-left + admission governance                            | `.github/` Trivy gate; `security/cosign`; `gitops/platform/security/kyverno-policies/` (`require-image-signature`, PSS) |
| 10  | **CI/CD automation**                  | Quality gates as code                                        | `.github/workflows/`, `Makefile`, `.pre-commit-config.yaml`, `yamllint`                                                 |
| 11  | **Progressive delivery**              | Canary as a platform primitive                               | `apps/seal/charts/seal/templates/rollout-api.yaml` (Argo Rollouts)                                                      |
| 12  | **Event-driven autoscaling**          | Scale on real signals, not just CPU                          | `apps/seal/charts/seal/templates/keda-scaledobject.yaml` (Redis list scaler)                                            |
| 13  | **Disaster recovery**                 | DR that is _exercised_, not just configured                  | `gitops/platform/storage/minio.yaml` (Velero backend); `tests/velero/`, `tests/db-backup/` (restore scenarios)          |
| 14  | **Developer experience / IDP**        | Self-service, golden paths                                   | `tools/atlasctl/cmd/*` (`new`, `enable`, `seed`, `backup`); `templates/gold/`; `apps/seal` Helm chart                   |
| 15  | **Bare-metal, no cloud lock-in**      | Cloud-free HA (no ELB/MetalLB/EBS)                           | Talos+Incus, Cilium LB VIP, Linstor, Zot cache — entire stack runs on Incus VMs                                         |

---

## How to use in an interview

- "Show me GitOps maturity" → #2 + `gitops/bootstrap/root-app.yaml`.
- "How do you do security?" → #9 (Trivy + Cosign + Kyverno signature gate + netpols).
- "What about storage without a cloud?" → #6 (Linstor DRBD, `autoPlace=2`).
- "Prove developer self-service" → #14 (`atlasctl new` → golden path → Argo CD).
- "How do you test DR?" → #13 (`tests/velero`, `tests/db-backup` restore runs).
