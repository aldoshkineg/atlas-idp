# Cluster Health Check

```bash
# 1. ArgoCD apps - all must be Synced + Healthy
kubectl get applications -n argocd

# 2. Gateway (Cilium, platform-gateway) - must be Programmed
kubectl get gateway -n kube-system

# 3. TLS certs - all must be True
kubectl get clusterissuer
kubectl get certificate -n kube-system

# 4. Test app via gateway (expect 200)
curl -sk --resolve "test-ca.atlas:443:127.0.0.1" \
  https://test-ca.atlas:443 -o /dev/null -w "%{http_code}"

# 5. Pods - all Running
kubectl get pods -A --field-selector status.phase=Running

# 6. Nodes - all Ready
kubectl get nodes
```

**Expected:** all green, no errors, test returns `200`.
