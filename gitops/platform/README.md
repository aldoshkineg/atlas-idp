# Platform Layer — Argo CD Applications

This directory contains Argo CD Application CRs for core platform services.

## Structure

All Applications in this directory are automatically discovered by the root Application (`gitops/bootstrap/root-app.yaml`) via directory recursion.

## Applications

| Application | Chart | Namespace | Purpose |
|-------------|-------|-----------|---------|
| **ingress-nginx** | kubernetes/ingress-nginx | ingress-nginx | Ingress controller (HTTP/HTTPS routing) |
| **cert-manager** | jetstack/cert-manager | cert-manager | TLS certificate management |
| **metrics-server** | kubernetes-sigs/metrics-server | kube-system | Resource metrics (CPU/memory for HPA) |
| **kube-prometheus-stack** | prometheus-community | monitoring | Prometheus + Grafana + Alertmanager |

## GitOps Flow

```
git push → GitHub repo
    ↓
Argo CD watches gitops/platform/
    ↓
Argo CD syncs Helm charts
    ↓
Kubernetes resources created
    ↓
Argo CD continuously monitors drift
```

## Adding New Platform Services

1. Create new Application CR: `gitops/platform/service-name.yaml`
2. Configure source (Helm chart or raw manifests)
3. Set sync policy (automated + prune + selfHeal)
4. Commit + push → Argo CD auto-syncs

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

# Check sync status
argocd app list

# Watch specific application
argocd app get ingress-nginx --refresh
```
