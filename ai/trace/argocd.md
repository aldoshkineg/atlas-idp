# ArgoCD GitOps Troubleshooting Prompt

## Context
- **ArgoCD CLI Connection:** `echo y | argocd login <CONTROL_PLANE_IP>:30080 --user admin --password <from-secret> --insecure`
  *(Note: Dynamically get the IP from the docker container: `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' atlas-idp-control-plane`)*
- **Repository:** `https://github.com/aldoshkineg/atlas-idp.git`, branch `main`
- **Directory Structure:**
  - `gitops/bootstrap/` — Root applications (root-apps / App-of-Apps pattern)
  - `gitops/platform/apps/` — ArgoCD `Application` manifests
  - `gitops/platform/configs/` — Runtime Kubernetes resources (sealed secrets, ingresses, etc.)

---

## Fast Feedback Loop (Testing WITHOUT Git Push)
To test changes locally before pushing to the remote repository, use ArgoCD's local routing feature:

```bash
# 1. Local dry-run (diff local files against live cluster without pushing to git)
argocd app diff <app-name> --local <path-to-local-dir-with-manifests>

# 2. Local sync (apply local changes directly via ArgoCD controller)
argocd app sync <app-name> --local <path-to-local-dir-with-manifests>

# 3. Local rendering check (if using Helm/Kustomize base)
helm template <release-name> ./chart
kustomize build <path-to-overlay>

```

---

## Quick Commands (Reuse in context)

```bash
# Status & Inspection
argocd app list
argocd app get <app-name>
argocd app manifests <app-name> | grep -E "kind:|name:"

# Sync & Refresh
argocd app sync <app-name> --timeout 600
argocd app get <app-name> --refresh

# Cluster Level Debug
kubectl get <resource> -n <ns>
kubectl describe <resource> <name> -n <ns>

```

---

## Common Issues & Verified Fixes

### 1. SyncError: Resource CRD not found

**Cause:** Application tries to apply a Custom Resource before its CRD is fully installed and recognized by the API server.
**Fix:** Use Sync Waves in `Application` metadata to delay resource creation.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0" # CRDs should be applied in a lower/negative wave

```

### 2. ComparisonError: field not declared in schema

**Cause:** Live resource mutates (due to admission controllers, default-injectors, or operators updating status) and conflicts with the Git state.
**Fix:** Add `ignoreDifferences` to the `Application` spec:

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers:
        - /status/terminatingReplicas

```

### 3. Namespace not found

**Fix:** Enable automatic namespace creation in the `Application` spec:

```yaml
spec:
  syncPolicy:
    syncOptions:
      - CreateNamespace=true

```

### 4. Helm repo 404 (OCI Registry)

**Fix:** Use the correct OCI registry format in the source definition:

```yaml
spec:
  source:
    repoURL: oci://ghcr.io/nginxinc/charts
    chart: nginx-gateway-fabric

```

### 5. Gateway API / Configs Race Condition

**Architecture Pattern:**

* `root-platform` scans ONLY `gitops/platform/apps/`.
* `platform-configs` application handles `gitops/platform/configs/` with `sync-wave: "2"`.
* Ensure `gitops/platform/configs/` is strictly excluded from the root application's automatic discovery path to avoid race conditions.

---

## Optimized Workflow

1. **Analyze:** Run `argocd app list` and `argocd app get <app> | grep -A10 CONDITION`.
2. **Edit:** Modify YAML files locally in `gitops/platform/apps/` or `gitops/platform/configs/`.
3. **Verify Locally:** Run `argocd app diff <app> --local .` to check the changes against the cluster.
4. **Apply Locally:** Run `argocd app sync <app> --local .` to test the fix instantly without git actions.
5. **Commit & Push:** Once verified, `git commit -m "fix: <comp> - <desc>"` and push to `main`.

---

## Token-Efficient Rules for LLM

* Keep code outputs concise. Use `| head -N` and `| grep` to limit log/manifest chunks.
* Do not suggest `git push` if the issue can be reproduced or verified locally via `argocd app diff --local`.
* When suggesting YAML changes, output ONLY the modified snippet with proper context indentation, not the entire file.
