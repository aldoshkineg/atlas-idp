# Platform Layer — Argo CD Applications

This directory contains Argo CD Application CRs for core platform services, organized as an app-of-apps pattern.

## Structure

All Applications in this directory are automatically discovered by the root Application (`gitops/bootstrap/root-app.yaml`) via directory recursion. The `values/` subdirectories contain Helm values files and are excluded from discovery.

## Applications

### Base Layer (wave 1)

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **metrics-server** | kubernetes-sigs/metrics-server | kube-system | Resource metrics for HPA |

### Networking Layer (waves 0–6)

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **gateway-api-crds** | kubernetes-sigs/gateway-api (config/crd) | default | Gateway API CRDs (v1.1.0) |
| **nginx-gateway-fabric** | nginx-gateway-fabric:v1.4.0 | nginx-gateway-fabric | Gateway API controller |
| **gateway-resources** | gitops/platform/layers/networking/values/gateway-resources | nginx-gateway-fabric | Gateway CR (platform-gateway) |
| **grafana-gateway** | gitops/platform/layers/networking/values/grafana-resources | monitoring | HTTPRoute + Certificate for grafana.atlas |
| **minio-gateway** | gitops/platform/layers/networking/values/minio-resources | minio | HTTPRoute + Certificate for s3.atlas |
| **vault-gateway** | gitops/platform/layers/networking/values/vault-resources | vault | HTTPRoute + Certificate for vault.atlas |

### Security Layer (waves 0–1)

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **cert-manager** | jetstack/cert-manager | cert-manager | TLS certificate management |
| **vault-operator** | bank-vaults/vault-operator | vault | HashiCorp Vault operator (Bank-Vaults) |
| **vault-secrets-webhook** | bank-vaults/secrets-webhook | vault | Vault secrets injection webhook |

### Storage Layer (waves 1–4)

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **snapshot-crds** | kubernetes-csi/external-snapshotter (client/config/crd) | kube-system | VolumeSnapshot CRDs |
| **snapshot-controller** | kubernetes-csi/external-snapshotter (deploy/kubernetes/snapshot-controller) | kube-system | Snapshot controller |
| **minio** | charts.min.io/minio | minio | S3-compatible object storage |
| **csi-hostpath** | raw manifests | storage | CSI hostpath driver for local PVs |
| **velero** | vmware-tanzu/velero | velero | Backup & disaster recovery |

### Observability Layer (waves 5–7)

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **prom-stack** | prometheus-community/kube-prometheus-stack | monitoring | Prometheus + Grafana + Alertmanager |
| **loki** | grafana/loki | loki | Log aggregation (SingleBinary) |
| **alloy** | grafana/alloy | alloy | Pod log collection DaemonSet |

## GitOps Flow

```
git push → GitHub repo
    ↓
Argo CD watches gitops/platform/layers/ (root-app with directory recursion)
    ↓
Argo CD syncs Applications:
    ↓
├── snapshot-crds         → VolumeSnapshot CRDs (wave 1)
├── snapshot-controller   → Snapshot controller (wave 2)
├── metrics-server        → Resource metrics (wave 1)
├── gateway-api-crds      → Gateway API CRDs (wave 0)
├── nginx-gateway-fabric  → NGINX Gateway controller (wave 2)
├── gateway-resources     → Gateway CR (wave 4)
├── cert-manager          → TLS certificates (wave 0)
├── vault-operator        → HashiCorp Vault operator (wave 0)
├── vault-secrets-webhook → Vault secrets injection (wave 1)
├── minio                 → S3 object storage (wave 3)
├── csi-hostpath          → CSI hostpath driver (wave 3)
├── velero                → Backup & DR (wave 4)
├── prom-stack            → Prometheus + Grafana (wave 5)
├── loki                  → Log aggregation (wave 6)
├── alloy                 → Log collection DaemonSet (wave 7)
├── grafana-gateway       → grafana.atlas HTTPRoute (wave 6)
├── minio-gateway         → s3.atlas HTTPRoute (wave 6)
└── vault-gateway         → vault.atlas HTTPRoute (wave 6)
```

## Adding New Platform Services

1. Create a new layer subdirectory: `gitops/platform/layers/<layer>/`
2. Create Application CR: `gitops/platform/layers/<layer>/<app-name>.yaml`
3. If using Helm, add values file: `gitops/platform/layers/<layer>/values/<app-name>.yaml`
4. Set sync policy (automated + prune + selfHeal)
5. Commit + push → Argo CD auto-syncs

## Verification

```bash
# Check all platform Applications
kubectl get applications -n argocd

# Check Gateway API CRDs and resources
kubectl get gatewayclass
kubectl get gateway -n nginx-gateway-fabric

# Watch NGINX Gateway Fabric pods
kubectl get pods -n nginx-gateway-fabric
```
