# Requirements

Single source of truth for pinned CLI tooling versions and platform sizing.

- `tools/ci/preflight.sh` parses [Local CLI Tooling](#local-cli-tooling) to verify installed binaries.
- `tools/ci/install-tools.sh` reads the same table to install the toolchain.

## Local CLI Tooling

| Tool           | Version            |
| -------------- | ------------------ |
| pre-commit     | 4.5.1              |
| terraform      | 1.15.3             |
| kubectl        | 1.34.0             |
| helm           | 3.19               |
| argocd         | 3.4.2              |
| age            | 1.3.1              |
| yq             | 4.2.0              |
| trivy          | 0.70.0             |
| docker         | 29.5.2             |
| docker compose | 5.1.4              |
| docker buildx  | 0.34.1             |
| go-task        | 3.52.0             |
| gh             | 2.93.0             |
| act            | 0.2.64             |
| jq             | 1.8.1              |
| velero         | 1.18.1             |
| mc             | RELEASE.2025-08-13 |
| yamllint       | 1.35.1             |
| shellcheck     | 0.10.0.1           |
| gitleaks       | 8.24.3             |
| golangci-lint  | 2.12.2             |
| atlasctl       | 0.60.0             |
| vault          | 1.18.0             |
| incus          | 7.2.0              |

## System Requirements

Sizing guidance for the Atlas IDP platform (Talos + Incus + Cilium + LINSTOR),
derived from the `stage` cluster (3 Talos VMs on one Incus host).

### TL;DR

- **Host:** ≥ 24 GiB RAM (the `stage` host has 15 GiB and swap-thrashes).
- **Control-plane VM:** ≥ 6 GiB RAM (apiserver ~2.2 GiB due to 147 CRDs).
- **Worker VM:** ≥ 8 GiB RAM each.
- **Boot disk / VM:** ≥ 20 GiB; **second disk / worker:** ≥ 20 GiB for LINSTOR.
- **vCPU:** 2 per node min, 4 recommended.

### Host (Incus)

| Resource | Minimum     | Recommended |
| -------- | ----------- | ----------- |
| RAM      | 16 GiB      | 24 GiB      |
| vCPU     | 6           | 12          |
| Disk     | 120 GiB SSD | 250 GiB SSD |

If `free -m` on the host shows `Swap: used > 0`, the VMs are overcommitted.

### VM sizing

| Node          | RAM (min/rec) | vCPU  | Boot disk   | LINSTOR disk        |
| ------------- | ------------- | ----- | ----------- | ------------------- |
| Control-plane | 4 / 6–8 GiB   | 2 / 4 | 20 / 40 GiB | — (diskless)        |
| Worker ×2     | 4 / 8 GiB     | 2 / 4 | 20 / 40 GiB | 20 / 40 GiB (block) |

### Notes

- Memory is the binding constraint, not CPU. A full rollout needs ~11.5 GiB pod RAM.
- Reduce the CRD count (147) to lower apiserver memory.
- Run `free -m` on the Incus host (not inside a VM) to check swap pressure.

## Cluster Runtime (IaC-managed)

| Component            | Version | Source                                                            |
| -------------------- | ------- | ----------------------------------------------------------------- |
| Talos OS             | v1.11.2 | `infra/environments/stage/variables.tf` (default `talos_version`) |
| Kubernetes           | v1.34.1 | `infra/environments/stage/variables.tf` (default `k8s_version`)   |
| Cilium (Helm chart)  | 1.19.4  | `infra/environments/stage`: `cilium_chart_version`                |
| Argo CD (Helm chart) | 7.7.5   | `infra/environments/stage`: `argocd_chart_version`                |
| Zot registry cache   | v2.1.16 | `infra/environments/stage/variables.tf`: `zot_image_ref`          |

## Platform Services (GitOps / Helm)

Chart versions are `targetRevision` values in the Argo CD `Application` manifests
under `gitops/platform/`.

| Application                  | Chart Version | Repo                                       | Manifest                                     |
| ---------------------------- | ------------- | ------------------------------------------ | -------------------------------------------- |
| gateway-api (CRDs)           | v1.2.1        | kubernetes-sigs/gateway-api                | `platform/base/gateway-api-crds.yaml`        |
| cert-manager                 | v1.16.2       | charts.jetstack.io                         | `platform/base/cert-manager.yaml`            |
| external-secrets             | 0.14.0        | charts.external-secrets.io                 | `platform/base/external-secrets.yaml`        |
| vault-operator (bank-vaults) | 1.24.0        | ghcr.io/bank-vaults/helm-charts            | `platform/base/vault-operator.yaml`          |
| vault-secrets-webhook        | 0.4.1         | ghcr.io/bank-vaults/helm-charts            | `platform/base/vault-secrets-webhook.yaml`   |
| linstor-operator             | 2.10.6        | ghcr.io/piraeusdatastore/piraeus-operator  | `platform/base/linstor-operator.yaml`        |
| linstor-cluster              | 1.1.1         | piraeusdatastore.github.io/helm-charts     | `platform/base/linstor-cluster.yaml`         |
| external-snapshotter (CRDs)  | v8.6.0        | kubernetes-csi/external-snapshotter        | `platform/base/snapshot-crds.yaml`           |
| trivy-operator               | 0.33.2        | aquasecurity.github.io/helm-charts         | `platform/security/trivy-operator.yaml`      |
| argo-rollouts (CRDs)         | v1.9.0        | argoproj/argo-rollouts                     | `platform/delivery/argo-rollouts-crds.yaml`  |
| argo-rollouts (Helm)         | 2.41.0        | argoproj.github.io/argo-helm               | `platform/delivery/argo-rollouts.yaml`       |
| keda                         | 2.14.0        | kedacore.github.io/charts                  | `platform/delivery/keda.yaml`                |
| Alloy (Grafana)              | 1.9.0         | grafana.github.io/helm-charts              | `platform/observability/alloy.yaml`          |
| Loki                         | 7.0.0         | grafana.github.io/helm-charts              | `platform/observability/loki.yaml`           |
| kube-prometheus-stack        | 68.2.0        | prometheus-community.github.io/helm-charts | `platform/observability/prom-stack.yaml`     |
| Tempo                        | 1.24.4        | grafana.github.io/helm-charts              | `platform/observability/tempo.yaml`          |
| metrics-server               | 3.12.2        | kubernetes-sigs.github.io/metrics-server   | `platform/observability/metrics-server.yaml` |
| MinIO                        | 5.4.0         | charts.min.io                              | `platform/storage/minio.yaml`                |
| Velero                       | 8.0.0         | vmware-tanzu.github.io/helm-charts         | `platform/storage/velero.yaml`               |
| CloudNativePG operator       | 0.28.3        | cloudnative-pg.github.io/charts            | `platform/storage/cnpg-operator.yaml`        |
| CNPG barman plugin           | 0.7.0         | cloudnative-pg.github.io/charts            | `platform/storage/cnpg-barman-plugin.yaml`   |
| Redis (Bitnami)              | 24.0.8        | bitnamicharts                              | `platform/storage/redis.yaml`                |

## Workloads

| Workload             | Image                                    | Version | Source                                                                |
| -------------------- | ---------------------------------------- | ------- | --------------------------------------------------------------------- |
| Seal (api/worker/ui) | ghcr.io/aldoshkineg/seal-{api,worker,ui} | v0.52.0 | `apps/seal` (in-repo demo app; images at ghcr.io/aldoshkineg/seal-\*) |
