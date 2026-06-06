# Platform Layer — Argo CD Applications

This directory contains Argo CD Application CRs for core platform services, organized as an app-of-apps pattern.

## Structure

All Applications in this directory are automatically discovered by the root Application (`gitops/bootstrap/root-app.yaml`) via directory recursion. The `values/` subdirectories contain Helm values files and are excluded from discovery.

## Applications

| Application | Chart/Source | Namespace | Purpose |
|-------------|---------------|-----------|---------|
| **metrics-server** | kubernetes-sigs/metrics-server | kube-system | Resource metrics for HPA |
| **gateway-api-crds** | kubernetes-sigs/gateway-api (config/crd) | default | Gateway API CRDs (v1.1.0) |
| **nginx-gateway-fabric** | nginx-gateway-fabric:v1.4.0 | nginx-gateway-fabric | Gateway API controller |
| **cert-manager** | jetstack/cert-manager | cert-manager | TLS certificate management |
| **test-app** | gitops/platform/layers/testing/resources | testing | Test service with TLS via Gateway |
| **monitoring** | prometheus-community/kube-prometheus-stack | monitoring | Prometheus + Grafana + Alertmanager |

## GitOps Flow

```
git push → GitHub repo
    ↓
Argo CD watches gitops/platform/layers/ (root-app with directory recursion)
    ↓
Argo CD syncs Applications:
    ↓
├── metrics-server       → Resource metrics (wave 1)
├── gateway-api-crds     → Gateway API CRDs (wave 0)
├── nginx-gateway-fabric → NGINX Gateway controller (wave 1)
├── cert-manager         → TLS certificate management (wave 1)
├── test-app             → Test service + Gateway + TLS cert (wave 3)
└── monitoring           → Prometheus + Grafana (wave 5)
```

## Adding New Platform Services

1. Create a new layer subdirectory: `gitops/platform/layers/<layer>/`
2. Create Application CR: `gitops/platform/layers/<layer>/<app-name>.yaml`
3. If using Helm, add values file: `gitops/platform/layers/<layer>/values/<app-name>.yaml`
4. Set sync policy (automated + prune + selfHeal)
5. Commit + push → Argo CD auto-syncs

## Adding Test Resources

1. Create Application CR in the relevant layer: `gitops/platform/layers/<layer>/<app-name>.yaml`
2. Place raw manifests in a `resources/` subdirectory
3. Point the Application's `source.path` to the `resources/` directory
4. The `resources/` path is excluded from root-app discovery to avoid double management

## Verification

```bash
# Check all platform Applications
kubectl get applications -n argocd

# Check Gateway API CRDs and resources
kubectl get gatewayclass
kubectl get gateway -n nginx-gateway-fabric

# Watch NGINX Gateway Fabric pods
kubectl get pods -n nginx-gateway-fabric

# Test TLS (requires /etc/hosts entry: 127.0.0.1 test-ca.atlas)
curl --cacert clusters/kind/certs/ca.crt https://test-ca.atlas/
```
