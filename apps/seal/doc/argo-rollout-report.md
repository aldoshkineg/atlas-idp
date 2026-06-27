# Argo Rollout Test Report

## Environment

- **Cluster:** kind (atlas-idp)
- **Namespace:** atlasteam-seal
- **Rollout:** `seal-api` (3 replics, Argo Rollouts controller)
- **Gateway:** nginx-gateway-fabric, HTTPRoute `seal` (managedRoute for traffic routing)
- **Analysis templates:** `seal-success-rate`, `seal-latency` (Prometheus-based)
- **Canary steps:** `setWeight 10 → pause 30s → setWeight 50 → pause 30s → setWeight 100`
- **Date:** 2026-06-27

## Test: `v0.40` tag

**Goal:** Verify full canary lifecycle — scaling, traffic shifting, pausing, and promotion.

The tag `v0.40` was pushed to GitHub, built by CI (`seal-docker-publish.yml`), and published as:

- `ghcr.io/aldoshkineg/seal-api:v0.40`
- `ghcr.io/aldoshkineg/seal-worker:v0.40`
- `ghcr.io/aldoshkineg/seal-ui:v0.40`

| Step | Event                                                                                  | Status |
| ---- | -------------------------------------------------------------------------------------- | ------ |
| 0    | Patch rollout image to `v0.40`                                                         | ✅     |
| 1    | New ReplicaSet `7db99dbd49` created (revision 6)                                       | ✅     |
| 2    | Canary pod started, became Ready (1/1), IP `10.0.1.72`                                 | ✅     |
| 3    | **Step 0** — `setWeight: 10` → 10% traffic to canary                                   | ✅     |
| 4    | **Step 1** — `pause: 30s` → rollout paused (phase `Paused`, message `CanaryPauseStep`) | ✅     |
| 5    | Canary endpoint `seal-api-canary` shows canary pod IP                                  | ✅     |
| 6    | **Step 2** — `setWeight: 50` → 50% traffic to canary                                   | ✅     |
| 7    | **Step 3** — `pause: 30s` → second pause                                               | ✅     |
| 8    | **Step 4** — `setWeight: 100` → all traffic to canary (promotion)                      | ✅     |
| 9    | Stable RS switched from `87668f65` (v0.35) to `7db99dbd49` (v0.40)                     | ✅     |
| 10   | Old ReplicaSet `87668f65` scaled down to 0                                             | ✅     |
| 11   | Rollout phase `Healthy`, step index 5 (all done)                                       | ✅     |
| 12   | Both services (`seal-api-stable`, `seal-api-canary`) point to the new pod              | ✅     |
| 13   | `https://seal.atlas/` returns **200 OK**                                               | ✅     |

## Observations

### Canary lifecycle

- Traffic routing via `managedRoutes` (HTTPRoute `seal`) works correctly — weight is updated at each step and nginx-gateway-fabric distributes accordingly.
- After promotion, the old ReplicaSet is scaled down within seconds.
- Rollout revision history (`revisionHistoryLimit: 3`) preserves old RS for fast rollback.

### Pause & resume

- Automatic pauses (`duration: 30s`) expire and the rollout progresses to the next step.
- Manual promote/abort not tested (plugin `kubectl-argo-rollouts` not installed).

### Analysis

- AnalysisTemplates `seal-success-rate` and `seal-latency` exist but **are not referenced** in the running Rollout's step definitions (the spec on the cluster omits the `analyses:` blocks present in the Helm template). This is an intermittent `OutOfSync` condition flagged by ArgoCD.
- Without analysis steps, the rollout relies solely on pod readiness probes for health checks.

## Recommendations

1. **Add `progressDeadlineSeconds: 300`** to the Rollout spec — enables automatic rollback if the canary does not become healthy within 5 minutes.
2. **Fix the canary steps** to include `analyses:` blocks referencing `seal-success-rate` and `seal-latency` — enables Prometheus-based canary validation (error rate, latency).
3. **Install `kubectl-argo-rollouts`** plugin for `promote`/`abort`/`retry` commands in future tests.
4. **Test with a deliberately degraded canary** (e.g. high-latency code, failing health endpoint) to verify that analysis thresholds trigger automatic rollback.

## Appendix: Commands Used

```bash
# Set image (trigger canary)
kubectl patch rollout seal-api -n atlasteam-seal --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "ghcr.io/aldoshkineg/seal-api:v0.40"}]'

# Watch rollout status
kubectl get rollout seal-api -n atlasteam-seal -o json | jq '{phase, currentStepIndex, message}'

# List pods
kubectl get pods -n atlasteam-seal -l app.kubernetes.io/name=seal-api -o wide

# Check traffic distribution
kubectl get endpoints -n atlasteam-seal seal-api-stable seal-api-canary

# Check ReplicaSets
kubectl get rs -n atlasteam-seal -l app.kubernetes.io/name=seal-api

# Disable/restore ArgoCD auto-sync
kubectl patch application atlasteam-seal -n argocd --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
kubectl patch application atlasteam-seal -n argocd --type json \
  -p='[{"op": "add", "path": "/spec/syncPolicy/automated", "value": {"prune": true, "selfHeal": true, "allowEmpty": false}}]'

# Push tag to trigger CI build
git tag v0.40 && git push origin v0.40
```
