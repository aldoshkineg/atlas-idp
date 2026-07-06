# GitOps Rename: platform-kind → platform — Remaining Issues

## Date: 2026-07-06

### 1. ArgoCD repo-server crashing (CRITICAL)

`argocd-repo-server` pods keep crashing (Error/Completed/OOM). Multiple pods restarted:

- `argocd-repo-server-774c9cf8c6-rnfqx` — Error (116m)
- `argocd-repo-server-774c9cf8c6-npjn8` — ContainerStatusUnknown
- `argocd-repo-server-774c9cf8c6-4nlcc` — Completed (9m)
- `argocd-repo-server-774c9cf8c6-ftrjz` — Pending

Service IP `10.110.58.84:8081` unreachable → ALL child Applications show ComparisonError:

```
rpc error: code = Unavailable desc = connection error:
desc = "transport: Error while dialing: dial tcp 10.110.58.84:8081:
connect: no route to host"
```

**Possible causes:**

- OOM due to many repos/charts being cached at once
- Some multi-source pattern causing repo-server to crash
- Too many concurrent manifest generations

**Fix:** Check repo-server logs, increase memory limits, or debug multi-source patterns.

---

### 2. CNPG Operator Duplicate (SharedResourceWarning)

Two Application CRDs manage the same resources:

- `cloudnativepg-operator` (created by root-app from git)
- `cnpg-operator` (created manually during wave deployment — already deleted)

Shared resources (ClusterRole, ClusterRoleBinding, Deployment, Webhooks, etc.)
warnings still persist. Need cleanup.

**Fix:** Delete one of the Applications. `cnpg-operator` was already deleted;
warnings should clear after next comparison.

---

### 3. gateway-resources OutOfSync/Healthy

The Cilium Gateway Application (`gateway-resources`) is OutOfSync.
Likely needs manual re-sync or depends on something not ready yet.

---

### 4. redis OutOfSync/Missing

Redis hasn't been created. Depends on `platform-secrets` and `kube-prometheus-stack`.

---

### 5. kube-prometheus-stack (Prometheus/Grafana) — Unknown/Progressing

Needs CRDs (PodMonitor, ServiceMonitor, etc.) — these are installed by the chart itself.
May need manual sync after repo-server is fixed.

---

### 6. ArgoCD application-controller Pending

`argocd-application-controller-0` is Pending — may be related to repo-server crash
or resource constraints.

---

### 7. Application Sync Order

Wave annotations are set but ArgoCD auto-sync will process them in order.
Need to verify after repo-server fix that all apps reconcile in correct order.

---

### 8. Resources Path on main

Resources (namespace.yaml, vault-cr.yaml, etc.) are now in `gitops/platform/...`
and accessible via multi-source paths. Verified that paths work correctly.

---

### 9. Privileged Namespace Labels

Need to ensure every namespace that requires privileged pod security is labeled:

- `piraeus-datastore` — ✅ (via `resources/linstor/namespace.yaml`)
- `vault` — ✅ (via `resources/vault/namespace.yaml`)
- Check if cert-manager needs privileged (webhooks with hostNetwork)

---

## Next Steps

1. Fix ArgoCD repo-server (check logs, increase memory, check config)
2. Wait for all apps to sync
3. Verify LINSTOR cluster is healthy
4. Verify Vault is unsealed and operational
5. Verify Cilium Gateway is ready
6. Uncomment workloads source in root-app.yaml when ready
7. Restore auto-sync on root-app (currently enabled)
