# Platform Layer — Argo CD Applications

This directory contains Argo CD Application CRs for core platform services.

## Structure

All Applications in this directory are automatically discovered by the root Application (`gitops/bootstrap/root-app.yaml`) via directory recursion.

## Applications

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **gateway-api-crds** | kubernetes-sigs/gateway-api (config/crd) | default | Gateway API CRDs (v1.1.0) |
| **nginx-gateway-fabric** | nginx-gateway-fabric:v1.4.0 | nginx-gateway-fabric | Gateway API controller |
| **gateway** | gitops/platform/gateway.yaml | gateway-api | Platform Gateway resource (HTTP listener) |
| **cert-manager** | jetstack/cert-manager | cert-manager | TLS certificate management |
| **metrics-server** | kubernetes-sigs/metrics-server | kube-system | Resource metrics (CPU/memory for HPA) |
| **kube-prometheus-stack** | prometheus-community | monitoring | Prometheus + Grafana + Alertmanager |

## GitOps Flow

```
git push → GitHub repo
    ↓
Argo CD watches gitops/platform/ (root-app with directory recursion)
    ↓
Argo CD syncs Applications:
    ↓
├── gateway-api-crds    → Installs Gateway API CRDs
├── nginx-gateway-fabric → Installs NGINX Gateway controller + GatewayClass
├── gateway             → Creates Gateway resource (HTTP listener on :80)
├── cert-manager       → TLS certificate management
├── metrics-server     → Resource metrics for HPA
└── monitoring         → Prometheus + Grafana
```

## Adding New Platform Services

1. Create new Application CR: `gitops/platform/service-name.yaml`
2. Or add raw manifests (like `gateway.yaml`) — Argo CD will discover them
3. Configure source (Helm chart or raw manifests)
4. Set sync policy (automated + prune + selfHeal)
5. Commit + push → Argo CD auto-syncs

## Resource Tuning

All Applications have resource limits tuned for kind (local dev). For AWS/EKS:
- Increase memory/CPU limits
- Enable persistent volumes (Grafana, Prometheus, Alertmanager)
- Enable HA mode (multiple replicas)
- Configure external storage (S3 for backups)

## Verification

```bash
# Check all platform Applications
kubectl get applications -n argocd

# Check Gateway API CRDs and resources
kubectl get gatewayclass
kubectl get gateway -n gateway-api

# Watch NGINX Gateway Fabric pods
kubectl get pods -n nginx-gateway-fabric

# Access Gateway (via NodePort 30080)
curl http://localhost:30080
```
