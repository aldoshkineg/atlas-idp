# ArgoCD GitOps Troubleshooting Prompt

## Context
- ArgoCD CLI connected: `echo y | argocd login 172.18.0.3:30080 --user admin --password <from-secret> --insecure`
- Repo: `https://github.com/aldoshkineg/atlas-idp.git`, branch `main`
- Structure: `gitops/bootstrap/` (root-apps), `gitops/platform/apps/` (Applications), `gitops/platform/configs/` (runtime resources)

## Quick Commands (reuse these)
```bash
# Status
argocd app list
argocd app get <app-name>

# Sync
argocd app sync <app-name> --timeout 600
argocd app manifests <app-name> | grep -E "kind:|name:"

# Debug
kubectl get <resource> -n <ns>
argocd app get <app-name> --refresh
```

## Common Issues & Fixes

### 1. SyncError: Resource CRD not found
**Cause**: App tries to apply resource before CRD installed
**Fix**: Use sync-waves + dependsOn, exclude from parent scan
```yaml
annotations:
  argocd.argoproj.io/sync-wave: "0"
dependsOn:
  - name: crd-app
```

### 2. ComparisonError: field not declared in schema
**Cause**: Status fields in live resource not in spec
**Fix**: Add ignoreDifferences
```yaml
ignoreDifferences:
  - group: apps
    kind: StatefulSet
    jsonPointers:
      - /status/terminatingReplicas
```

### 3. Namespace not found
**Fix**: Add to Application spec:
```yaml
syncOptions:
  - CreateNamespace=true
```

### 4. Helm repo 404
**Fix**: Use OCI registry format:
```yaml
repoURL: oci://ghcr.io/nginxinc/charts
```

### 5. Gateway API race condition
**Structure**:
- `root-platform` scans `gitops/platform/apps/` only
- `platform-configs` (wave 2) applies `configs/` with `dependsOn: nginx-gateway-fabric`
- Exclude `configs/` from root scan

## Workflow
1. `argocd app list` - check STATUS/HEALTH
2. `argocd app get <app> | grep -A10 CONDITION` - see errors
3. Edit yaml in `gitops/platform/apps/`
4. `git commit -m "fix: <issue>" && git push origin main`
5. Wait 30s for ArgoCD cache refresh
6. `argocd app sync <app> --timeout 600`

## Token-Efficient Debugging
- Use `| head -N` and `| grep` to limit output
- Check `argocd app list` first (concise overview)
- Only use `--refresh` when cache is stale
- Reuse commit messages: "fix: <component> - <short description>"
- Group related fixes in single commit when possible
