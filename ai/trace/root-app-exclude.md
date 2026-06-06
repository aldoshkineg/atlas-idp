# Root-App Exclude Pattern Fix

## Problem
`root-platform` app-of-apps failed to sync — CRDs not found for `Gateway`, `ClusterIssuer`, `Certificate`, `HTTPRoute`.

```
SyncFailed: The Kubernetes API could not find gateway.networking.k8s.io/Gateway
           The Kubernetes API could not find cert-manager.io/ClusterIssuer
```

## Root Cause
`root-app.yaml` had invalid `exclude` glob pattern:

```yaml
exclude: 'README.md|values|resources'
```

`|` is **literal** in glob (not OR). No files were excluded. Root-app picked up raw resource YAMLs from `testing/resources/` and tried to sync them directly, but CRDs weren't installed yet (child apps hadn't synced).

## Fix

**`gitops/bootstrap/root-app.yaml`:**
```yaml
exclude: '{README.md,**/values/**,**/resources/**}'
```

Brace expansion `{a,b}` is valid in doublestar (glob lib used by ArgoCD). `**/resources/**` matches any `resources/` dir at any depth.

**`gitops/platform/layers/security/cert-manager.yaml`:**
sync-wave: `"1"` → `"0"` — cert-manager must install CRDs before apps that depend on them.

**`gitops/platform/layers/networking/gateway-api.yaml`:**
nginx-gateway-fabric sync-wave: `"1"` → `"2"` — nginx needs CRDs from gateway-api-crds (wave 0) + cert-manager (wave 0) before creating Gateway/HTTPRoute.

## Sync Order (Waves)
| Wave | App | CRDs Installed |
|------|-----|----------------|
| 0 | gateway-api-crds | gateway.networking.k8s.io |
| 0 | cert-manager | cert-manager.io |
| 1 | metrics-server | — |
| 2 | nginx-gateway-fabric | needs wave 0 CRDs |
| 3 | test-app | needs wave 0+2 CRDs |
| 5 | kube-prometheus-stack | — |

## Recovery
1. `kubectl patch application root-platform -n argocd --type merge -p '{"spec":{"source":{"directory":{"exclude":"{README.md,**/values/**,**/resources/**}"}}}}'`
2. Clear stuck operation: `kubectl patch application root-platform -n argocd --type json -p='[{"op": "remove", "path": "/status/operationState"}]'`
3. Force hard refresh: `kubectl annotate application root-platform -n argocd argocd.argoproj.io/refresh=hard --overwrite`
