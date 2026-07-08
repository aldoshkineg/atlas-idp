# Requirements & Version Matrix

Pinned versions of the local CLI tooling (`infra/` IaC) and platform applications
installed into the cluster via `gitops/` (Argo CD / Helm). Versions are sourced
from `versions.tf`, `*.tf` variables, `.terraform.lock.hcl`, and Argo CD
`Application` manifests.

> Last updated: 2026-07-08

## Local CLI Tooling

| Tool           | Version            |
| -------------- | ------------------ |
| pre-commit     | 4.5.1              |
| terraform      | 1.15.3             |
| kubectl        | 1.34.0             |
| kind           | 0.29.0             |
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

## Terraform Providers

Exact resolved versions from `.terraform.lock.hcl`; constraint in `versions.tf`.

| Provider             | Resolved | Constraint | Env        |
| -------------------- | -------- | ---------- | ---------- |
| hashicorp/helm       | 2.17.0   | ~> 2.14    | dev, stage |
| hashicorp/kubernetes | 2.38.0   | ~> 2.33    | dev, stage |
| hashicorp/local      | 2.9.0    | ~> 2.5     | dev, stage |
| hashicorp/null       | 3.3.0    | ~> 3.2     | dev, stage |
| hashicorp/random     | 3.9.0    | ~> 3.6     | dev, stage |
| kreuzwerker/docker   | 3.9.0    | ~> 3.0     | dev        |
| tehcyx/kind          | 0.7.0    | 0.7.0      | dev        |
| lxc/incus            | 1.1.1    | ~> 1.1     | stage      |
| siderolabs/talos     | 0.11.0   | ~> 0.7     | stage      |
| devops-rob/terracurl | 1.2.2    | ~> 1.0     | stage      |

## Cluster Runtime (IaC-managed)

| Component             | Version | Source                                                            |
| --------------------- | ------- | ----------------------------------------------------------------- |
| Talos OS              | v1.11.2 | `infra/environments/stage/variables.tf` (default `talos_version`) |
| Kubernetes            | v1.34.1 | `infra/environments/stage/variables.tf` (default `k8s_version`)   |
| Kubernetes (dev/kind) | v1.35.0 | `infra/environments/dev/main.tf`                                  |
| Cilium (Helm chart)   | 1.19.4  | `infra/environments/{dev,stage}`: `cilium_chart_version`          |
| Argo CD (Helm chart)  | 7.7.5   | `infra/environments/{dev,stage}`: `argocd_chart_version`          |
| Zot registry cache    | v2.1.16 | `infra/environments/stage/variables.tf`: `zot_image_ref`          |

> Talos is pinned via the `talos_version` variable; the Incus/Talos image is
> `ncloud-amd64.qcow2` for `talos_version` (with `-drbd` alias).

## Platform Services (GitOps / Helm charts)

Chart versions are `targetRevision` values in the Argo CD `Application` manifests
under `gitops/platform/`.

| Application                  | Chart / CRD Version                      | Repo                                       | Manifest                                     |
| ---------------------------- | ---------------------------------------- | ------------------------------------------ | -------------------------------------------- |
| gateway-api (CRDs)           | v1.2.1                                   | kubernetes-sigs/gateway-api                | `platform/base/gateway-api-crds.yaml`        |
| cert-manager                 | v1.16.2                                  | charts.jetstack.io                         | `platform/base/cert-manager.yaml`            |
| external-secrets             | 0.14.0                                   | charts.external-secrets.io                 | `platform/base/external-secrets.yaml`        |
| vault-operator (bank-vaults) | 1.24.0                                   | ghcr.io/bank-vaults/helm-charts            | `platform/base/vault-operator.yaml`          |
| vault-secrets-webhook        | 0.4.1                                    | ghcr.io/bank-vaults/helm-charts            | `platform/base/vault-secrets-webhook.yaml`   |
| linstor-operator             | 2.10.6                                   | ghcr.io/piraeusdatastore/piraeus-operator  | `platform/base/linstor-operator.yaml`        |
| linstor-cluster              | 1.1.1                                    | piraeusdatastore.github.io/helm-charts     | `platform/base/linstor-cluster.yaml`         |
| external-snapshotter (CRDs)  | v8.6.0                                   | kubernetes-csi/external-snapshotter        | `platform/base/snapshot-crds.yaml`           |
| trivy-operator               | 0.33.2                                   | aquasecurity.github.io/helm-charts         | `platform/security/trivy-operator.yaml`      |
| argo-rollouts (CRDs)         | v1.9.0                                   | argoproj/argo-rollouts                     | `platform/delivery/argo-rollouts-crds.yaml`  |
| argo-rollouts (Helm)         | 2.41.0                                   | argoproj.github.io/argo-helm               | `platform/delivery/argo-rollouts.yaml`       |
| keda                         | 2.14.0                                   | kedacore.github.io/charts                  | `platform/delivery/keda.yaml`                |
| Alloy (Grafana)              | 1.9.0 (image v0.91.0)                    | grafana.github.io/helm-charts              | `platform/observability/alloy.yaml`          |
| Loki                         | 7.0.0                                    | grafana.github.io/helm-charts              | `platform/observability/loki.yaml`           |
| kube-prometheus-stack        | 68.2.0                                   | prometheus-community.github.io/helm-charts | `platform/observability/prom-stack.yaml`     |
| Tempo                        | 1.24.4                                   | grafana.github.io/helm-charts              | `platform/observability/tempo.yaml`          |
| metrics-server               | 3.12.2                                   | kubernetes-sigs.github.io/metrics-server   | `platform/observability/metrics-server.yaml` |
| MinIO                        | 5.4.0                                    | charts.min.io                              | `platform/storage/minio.yaml`                |
| Velero                       | 8.0.0 (image 1.33.4, aws-plugin v1.10.0) | vmware-tanzu.github.io/helm-charts         | `platform/storage/velero.yaml`               |
| CloudNativePG operator       | 0.28.3                                   | cloudnative-pg.github.io/charts            | `platform/storage/cnpg-operator.yaml`        |
| CNPG barman plugin           | 0.7.0                                    | cloudnative-pg.github.io/charts            | `platform/storage/cnpg-barman-plugin.yaml`   |
| Redis (Bitnami)              | 24.0.8                                   | bitnamicharts                              | `platform/storage/redis.yaml`                |

## Application Container Images (non-Helm)

| Image                           | Version    | Source                                                                  |
| ------------------------------- | ---------- | ----------------------------------------------------------------------- |
| hashicorp/vault                 | 1.18.0     | `platform/base/resources/vault/vault-cr.yaml`                           |
| ghcr.io/bank-vaults/bank-vaults | v1.33.1    | `platform/base/resources/vault/vault-cr.yaml`                           |
| bitnamilegacy/kubectl           | 1.33.4     | `platform/base/resources/*/wait-*.yaml`, `platform/storage/velero.yaml` |
| ghcr.io/aldoshkineg/pause       | 3.10-amd64 | `infra/environments/stage/variables.tf`: `pause_image`                  |

## Workloads (external repos / images)

| Workload             | Image                                    | Version | Source                                         |
| -------------------- | ---------------------------------------- | ------- | ---------------------------------------------- |
| Seal (api/worker/ui) | ghcr.io/aldoshkineg/seal-{api,worker,ui} | v0.25.0 | `AGENTS.md` (app repo `aldoshkineg/atlas-dip`) |

## Notes

- The `dev` environment provisions a kind cluster; `stage` provisions a Talos/Incus
  cluster. Provider sets differ between the two (see table above).
- Terraform `required_version` is `>= 1.9.0` across all environments.
- All GitOps `Application` manifests point at `targetRevision: main` of this repo
  for local manifests, and at pinned tags for upstream Helm charts / CRDs.
- `atlasctl` builds use `VERSION=dev` unless overridden by the release workflow
  (`-ldflags "-X .../cmd.Version=<git tag>"`).
