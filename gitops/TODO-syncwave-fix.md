# Sync-Wave + Dependencies Fix Plan

## Root Cause Analysis

### Problem
Argo CD sync-waves and `depends-on` do not prevent downstream services from deploying
before their secrets exist. The chain breaks because:

1. **No health check for ExternalSecret** — Argo CD considers `platform-secrets`
   Application "Healthy" as soon as the ExternalSecrets resources are created in the
   Kubernetes API, regardless of whether they have actually synced data from Vault.
   `status.conditions[?type==Ready].status==True` is never checked.

2. **Depends-on gaps** — Several Applications lack explicit dependencies:
   - `vault-operator` needs `csi-hostpath` (Vault CR uses `csi-hostpath-sc` PVC)
   - `external-secrets` needs `vault-operator` (ClusterSecretStore targets Vault)
   - `velero` needs `platform-secrets` (velero-aws secret from Vault)
   - `kube-prometheus-stack` needs `platform-secrets` (grafana-admin secret from Vault)

3. **vault-token from CI** — ClusterSecretStore references `vault-token` secret in
   `external-secrets` namespace, which is only created by the CI pipeline's
   `vault-seeds` step. Argo CD cannot make secrets available without external CI.

### Resulting failure sequence
```
terraform apply
  └─ kind + Cilium + Argo CD + root-app (2 min)
     └─ Argo CD syncs ALL apps immediately
        ├─ vault-operator (wave 0) → vault CR → vault-0 pod (CSI pending)
        ├─ csi-hostpath (wave 2) → StorageClass created
        ├─ external-secrets (wave 3) → ESO installed + ClusterSecretStore
        ├─ platform-secrets (wave 4) → ExternalSecrets created → Argo CD: Healthy
        ├─ minio (wave 5, depends platform-secrets) → Argo CD sees Healthy → deploys
        │  └─ pod fails: secret "minio-auth" not found (ESO can't reach Vault: no token)
        ├─ velero (wave 5) → same failure
        └─ prom-stack (wave 6) → grafana fails: secret "grafana-admin" not found
CI vault-seeds (runs AFTER terraform apply)
  └─ waits for vault-0 → creates vault-token → seeds secrets
     └─ ESO reconciles → secrets created → but pods are already stuck
```

## Proposed Fixes

### 1. Switch ClusterSecretStore to vault-unseal-keys
**File:** `gitops/platform-kind/layers/security/resources/external-secrets/cluster-secret-store.yaml`

The Vault operator automatically creates `vault-unseal-keys` Secret (with key `vault-root`)
in the `vault` namespace when the Vault CR is reconciled. No external CI needed.

```diff
 auth:
   tokenSecretRef:
-    name: vault-token
-    key: token
-    namespace: external-secrets
+    name: vault-unseal-keys
+    key: vault-root
+    namespace: vault
```

This eliminates the CI `vault-seeds` dependency for ESO authentication. The CI step still
needs to write **secret data** (minio creds, grafana admin, etc.) into Vault.

### 2. Add Lua health check for ExternalSecret
**File:** `infra/modules/argocd-bootstrap/main.tf`

Argo CD needs to understand when an ExternalSecret is truly healthy (synced from Vault).
Add `configs.cm` with a Lua resource customization:

```lua
resource.customizations.health.external-secrets.io_ExternalSecret: |
  hs = {}
  if obj.status ~= nil and obj.status.conditions ~= nil then
    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Ready" then
        if condition.status == "True" then
          hs.status = "Healthy"
          hs.message = condition.message or "synced"
        elseif condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message or "sync error"
        else
          hs.status = "Progressing"
          hs.message = condition.message or "unknown"
        end
        return hs
      end
    end
  end
  hs.status = "Progressing"
  hs.message = "waiting for sync"
  return hs
```

### 3. Fix depends-on chains
Files and changes:

| File | Current | Fix |
|---|---|---|
| `gitops/.../security/vault-operator.yaml` | (no depends-on) | `depends-on: csi-hostpath` |
| `gitops/.../security/external-secrets.yaml` | (no depends-on) | `depends-on: vault-operator` |
| `gitops/.../storage/velero.yaml` | `depends-on: minio` | `depends-on: minio, platform-secrets` |
| `gitops/.../observability/prom-stack.yaml` | (no depends-on) | `depends-on: platform-secrets` |

### 4. Verify CI vault-seeds step
The CI `vault-seeds` action no longer needs to create `vault-token` secret (Fixes 1
eliminates it). It still needs to write platform secrets into Vault.

---

## Expected flow after fixes

```
terraform apply
  └─ kind + Cilium + Argo CD (with Lua health check)
     └─ root-app applied → Argo CD starts sync

Wave -1: AppProject platform-kind ✅
Wave 0:  cert-manager, vault-operator
         └─ vault-operator BLOCKED: depends-on csi-hostpath (wave 2)
Wave 1:  cert-manager-issuers, cnpg-operator, gateway-api-crds ✅
Wave 2:  csi-hostpath, snapshot-crds, metrics-server
         └─ csi-hostpath Ready → vault-operator UNBLOCKED
         └─ vault-operator syncs → operator + Vault CR → vault-0 pod starts
Wave 3:  external-secrets (depends-on vault-operator)
         └─ ESO installed → ClusterSecretStore points to vault-unseal-keys
         └─ Store validates: vault-0 is running, vault-unseal-keys exists → Ready
Wave 4:  platform-secrets (depends-on external-secrets, vault-operator)
         └─ ExternalSecrets created → ESO tries to read from Vault
         └─ Data NOT yet in Vault (CI hasn't run vault-seeds)
         └─ Lua health check → "Degraded" (Ready: False)
         └─ BLOCKS all downstream waves

CI vault-seeds:
  └─ Waits for vault-0 Ready
  └─ Writes platform secrets into Vault (kv put secret/platform/minio ...)
  └─ ESO retries (refreshInterval: 1m) → reads data → Ready: True
  └─ Lua health check → "Healthy"
  └─ platform-secrets Application Healthy → UNBLOCK

Wave 5:  minio, velero, gateway-resources
         └─ minio: existingSecret minio-auth EXISTS → pod starts successfully
         └─ velero: existingSecret velero-aws EXISTS → pod starts successfully
Wave 6:  kube-prometheus-stack, redis
         └─ grafana: secret grafana-admin EXISTS → pod starts successfully
```

## Files changed (8 files + 1 README)

```
# Argo CD config (resource customization)
M infra/modules/argocd-bootstrap/main.tf

# Security layer
M gitops/platform-kind/layers/security/resources/external-secrets/cluster-secret-store.yaml
M gitops/platform-kind/layers/security/vault-operator.yaml
M gitops/platform-kind/layers/security/external-secrets.yaml

# Storage layer
M gitops/platform-kind/layers/storage/velero.yaml

# Observability layer
M gitops/platform-kind/layers/observability/prom-stack.yaml

# CI
M .github/actions/vault-seeds/action.yml

# Docs
M security/vault/README.md
```

## Remaining concerns

1. **vault-seeds refresh timing** — ESO retries on `refreshInterval: 1m`. After
   vault-seeds writes data, it may take up to 1 minute for ExternalSecrets to sync.
   Consider lowering to `10s` for dev, or add a CI wait loop after vault-seeds.

2. **vault-operator → csi-hostpath wave paradox** — vault-operator is annotated wave 0
   but depends-on csi-hostpath (wave 2). Argo CD respects `depends-on` over wave
   ordering. vault-operator will wait. This is correct.

3. **Minio PVC** — minio also uses `storageClassName: csi-hostpath-sc` and already has
   `depends-on: csi-hostpath`. No change needed.