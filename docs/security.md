# Security Baseline — Network Policy, Kyverno, Supply Chain

Defense in depth: zero-trust pod networking (CiliumNetworkPolicy), admission control
(Kyverno, including Cosign signature verification), image/IaC scanning (Trivy) and
least-privilege RBAC. All of it is GitOps-managed in the `security` layer.

## Components

| Component        | App manifest (`gitops/platform/security/`) | Chart / version         | Wave |
| ---------------- | ------------------------------------------ | ----------------------- | ---- |
| kyverno-crds     | `kyverno-crds.yaml` (local path)           | —                       | 4    |
| Kyverno          | `kyverno.yaml`                             | `kyverno` 3.3.8         | 5    |
| kyverno-policies | `kyverno-policies.yaml` (local path)       | —                       | 6    |
| Trivy Operator   | `trivy-operator.yaml`                      | `trivy-operator` 0.33.2 | 8    |
| network-policies | `netpol.yaml` (local path)                 | —                       | 10   |

## Network isolation (CiliumNetworkPolicy)

`gitops/platform/security/resources/network-policies/` — one `platform-ingress` CNP per
platform namespace (12 total: argocd, vault, external-secrets, monitoring, loki, minio,
database, redis, cnpg-system, kube-system, velero, keda). Model:

- `endpointSelector: {}` → **default-deny ingress** for the whole namespace.
- Explicit allows: same-namespace traffic, `monitoring` (Prometheus scrape / Alloy),
  declared cross-namespace dependencies (e.g. `database` + `velero` + `atlasteam-seal` →
  `minio:9000`; `keda` + `atlasteam-seal` → `redis:6379`).
- `fromEntities: remote-node` — kubelet probes and API-server webhooks.
- `fromEntities: ingress` — traffic routed by the Cilium Gateway (identity
  `reserved:ingress`, **not** `world`). Required for every namespace behind a route.

Workload-level policies are not hand-written: `atlasctl new` generates a namespace
`NetworkPolicy` and a `CiliumClusterwideNetworkPolicy` (access to database/redis/minio)
from `templates/gold/infra/` — see [`workloads.md`](workloads.md).

## Admission control (Kyverno)

`gitops/platform/security/kyverno-policies/` — five ClusterPolicies targeting Pods
(platform namespaces excluded):

| Policy                    | Action      | Rule                                                                                                       |
| ------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------- |
| `require-image-signature` | **Enforce** | Cosign verification for `ghcr.io/aldoshkineg/*` (key = `security/cosign/cosign.pub`, `mutateDigest: true`) |
| `disallow-privileged`     | Audit       | no `privileged: true`, no `hostPath` volumes                                                               |
| `require-run-as-non-root` | Audit       | pod `runAsNonRoot: true`                                                                                   |
| `disallow-latest-tag`     | Audit       | image tag must not be `:latest`                                                                            |
| `require-labels`          | Audit       | `app.kubernetes.io/name` + `app.kubernetes.io/instance`                                                    |

The signature policy is the hard gate: an unsigned image in a workload namespace is
rejected at admission. Signing happens in CI — see [`cosign.md`](cosign.md).

## Scanning & runtime posture

- **CI (shift-left):** `make validate-security` → Trivy `HIGH,CRITICAL` over `infra/` and
  `gitops/`; config in `security/trivy/trivy.yaml`, exceptions in `.trivyignore`.
- **In-cluster:** Trivy Operator (ns `trivy-system`) with config-audit reports;
  image/secret scanning disabled to keep the lab footprint small, node collector
  excluded (Talos hostPath restrictions).

## RBAC

`security/rbac/` defines two ClusterRoles bound to groups: `platform-admin`
(`atlas:platform-admin`, full access) and `readonly` (`atlas:readonly`,
get/list/watch). Applied outside GitOps: `make rbac-apply` / `make rbac-delete`.

## Real usage

```bash
make test-network-policy   # 3-pod connectivity matrix: asserts allowed AND denied paths
make validate-security     # Trivy IaC gate (same as CI)
make seal-verify           # cosign verify of the published seal images
kubectl get cnp -A         # live CiliumNetworkPolicies
kubectl get clusterpolicy  # Kyverno policies + ready state
```

The netpol test (`tests/network-policy/`) deploys alpha/beta/gamma pods with two allow
policies and probes all six directions — proving both connectivity and **denial**.

## See also

- [`cosign.md`](cosign.md) — signing pipeline, key rotation, troubleshooting
- [`cilium.md`](cilium.md) — the dataplane enforcing the policies
- [`ca.md`](ca.md) — private PKI behind all the TLS
