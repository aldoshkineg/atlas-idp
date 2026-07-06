# ADR-005: Infrastructure Secrets Management via ESO + kms.vyrn.ru

## Status

Accepted

## Context

The repository contains two types of secrets:

1. **Infrastructure secrets** — for installing platform services (MinIO, Redis, Velero, CNPG backup). They are stored as Helm values inline or raw Secret manifests in git. 7 files with plaintext passwords.

2. **Application secrets** — for the Seal application (postgres, redis, minio credentials, pdf-signer cert). The architectural solution for these is HashiCorp Vault Agent Injector (stage 2, separate).

Problem: infrastructure secrets are stored in plaintext in a public git repository.

An external Vault server `kms.vyrn.ru:8200` (HTTPS, public certificate) is available with an existing Vault token.

## Decision

**External Secrets Operator (ESO)** reads secrets from `kms.vyrn.ru` and creates Kubernetes Secrets in the cluster. Helm charts reference these Secrets.

### Architecture

```
┌─────────────────────────────────┐
│ kms.vyrn.ru:8200                │
│  secret/data/platform/minio     │
│    → rootUser, rootPassword     │
│  secret/data/platform/redis     │
│    → redis-password             │
│  secret/data/platform/backups   │
│    → ACCESS_KEY_ID,             │
│      ACCESS_SECRET_KEY          │
│  kv/data/seal/seal-api          │
│    → postgres_password,         │
│      redis_password             │
│  kv/data/seal/seal-worker       │
│    → minio_access_key,          │
│      minio_secret_key,          │
│      redis_password             │
│  kv/data/seal/pdf-signer        │
│    → cert, key                  │
└──────────────┬──────────────────┘
               │ ESO (ExternalSecret → watch)
               ▼
┌─────────────────────────────────┐
│ K8s Secret (in service namespace)│
│  minio-credentials              │
│  velero-credentials             │
│  redis-auth                     │
│  production-db-backup           │
└──────────────┬──────────────────┘
               │ Helm chart / Deployment
               ▼
         Service uses Secret
```

### Authentication

ESO connects to `kms.vyrn.ru` using a **Vault Token**.

The token is stored in:

- GitHub Secrets (`VAULT_TOKEN`) — for CI
- K8s Secret `vault-token` in namespace `external-secrets` — created via Terraform `kubernetes_secret` resource

The ClusterSecretStore references this K8s Secret:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: kms-vyrn
spec:
  provider:
    hashicorpVault:
      server: https://kms.vyrn.ru:8200
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

### Vault Seeding

Initial seeding — **one-time manual** via Vault CLI:

```bash
# Set environment variables
export VAULT_ADDR=https://kms.vyrn.ru:8200
export VAULT_TOKEN=<token>

# Platform secrets
vault kv put secret/data/platform/minio \
  rootUser=minioadmin \
  rootPassword=minioadminpassword

vault kv put secret/data/platform/redis \
  redis-password=super-secret-redis

vault kv put secret/data/platform/backups \
  ACCESS_KEY_ID=minioadmin \
  ACCESS_SECRET_KEY=minioadminpassword

# Application secrets (for stage 2)
vault kv put kv/data/seal/seal-api \
  postgres_password=... \
  redis_password=...

vault kv put kv/data/seal/seal-worker \
  minio_access_key=minioadmin \
  minio_secret_key=minioadminpassword \
  redis_password=...

vault kv put kv/data/seal/pdf-signer \
  cert=@tls.crt \
  key=@tls.key
```

On redeployment (CI) secrets already exist — no seeding required.

### Files Changed

#### 1. New Components (Argo CD Application)

`gitops/platform/layers/security/external-secrets.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: platform
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: 0.14.0
    helm:
      values: |
        installCRDs: true
        serviceAccount:
          create: true
          name: external-secrets
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### 2. ClusterSecretStore

`gitops/platform/layers/security/resources/external-secrets/store.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: kms-vyrn
spec:
  provider:
    hashicorpVault:
      server: https://kms.vyrn.ru:8200
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

Managed by a separate Application `external-secrets-store` (sync-wave 3, after ESO).

#### 3. Vault Token into the Cluster

Token is created via Terraform as a K8s Secret:

```hcl
# infra/environments/dev/main.tf
resource "kubernetes_secret" "vault_token" {
  metadata {
    name      = "vault-token"
    namespace = "external-secrets"
  }
  data = {
    token = var.vault_token
  }
}
```

`vault_token` is passed via `TF_VAR_vault_token` from GitHub Secrets.

#### 4. Helm charts: inline values → existingSecret

**`minio.yaml`:**

```yaml
# Before
values: |
  rootUser: minioadmin
  rootPassword: minioadminpassword

# After
values: |
  existingSecret: minio-credentials
```

Plus ExternalSecret `gitops/platform/layers/storage/resources/minio/external-secret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-credentials
  namespace: minio
spec:
  secretStoreRef:
    name: kms-vyrn
    kind: ClusterSecretStore
  target:
    name: minio-credentials
  data:
    - secretKey: rootUser
      remoteRef:
        key: secret/data/platform/minio
        property: rootUser
    - secretKey: rootPassword
      remoteRef:
        key: secret/data/platform/minio
        property: rootPassword
```

And Application `gitops/platform/layers/storage/minio-secret.yaml` (sync-wave 4, before minio wave 5).

**`velero.yaml`:**

```yaml
# Before
credentials:
  useSecret: true
  secretContents:
    cloud: |
      [default]
      aws_access_key_id = minioadmin
      aws_secret_access_key = minioadminpassword

# After
credentials:
  useSecret: true
  existingSecret: velero-credentials
```

Plus ExternalSecret + Application.

**`resources/redis/secret.yaml` — replaced with ExternalSecret:**

```yaml
# Before
apiVersion: v1
kind: Secret
---
# After
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-auth
  namespace: redis
spec:
  secretStoreRef:
    name: kms-vyrn
    kind: ClusterSecretStore
  target:
    name: redis-auth
  data:
    - secretKey: redis-password
      remoteRef:
        key: secret/data/platform/redis
        property: redis-password
```

**`resources/postgres-cluster/backup-secret.yaml` — similarly:**

```yaml
# Before
apiVersion: v1
kind: Secret
---
# After
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
---
data:
  - secretKey: ACCESS_KEY_ID
    remoteRef:
      key: secret/data/platform/backups
      property: ACCESS_KEY_ID
  - secretKey: ACCESS_SECRET_KEY
    remoteRef:
      key: secret/data/platform/backups
      property: ACCESS_SECRET_KEY
```

#### 5. `seal.yaml` (workloads)

In stage 1 — unchanged (`vault.enabled: false`, secrets in `.Values.secrets.*`). In stage 2, Vault Agent Injector will be enabled with reads from `kms.vyrn.ru`.

### Sync Waves

```
Wave 1: vault-operator, cert-manager
Wave 2: vault-secrets-webhook, cert-manager-issuers
Wave 3: external-secrets (ESO controller) + external-secrets-store (ClusterSecretStore)
Wave 4: minio-secret, velero-secret, redis-secret (ExternalSecret CRs)
Wave 5: minio, velero (Helm charts with existingSecret)
Wave 6: redis, kube-prometheus-stack
Wave 7+: remaining services
```

### Pre-commit hooks

No changes required — all manifests remain valid YAML (ExternalSecret is a CRD with plain references, no secret values). `yamllint` and `trivy` work as usual.

## Consequences

### Pros

- No secrets in git (neither plaintext nor encrypted)
- Vault is the single source of truth
- ESO supports auto-refresh when secrets change in Vault
- Valid YAML in git (readable diffs, linting works)
- Centralized access audit for secrets (kms.vyrn.ru audit log)

### Cons

- Need to rewrite 5+ manifests (structural changes)
- Adds ESO controller (another component in the cluster)
- Sync timing dependency: kms.vyrn.ru must be reachable
- Vault token in Terraform state (S3, acceptable for dev)
- Initial Vault seeding is manual (one-time)

### Next Steps

- Stage 2: Vault Agent Injector for Seal applications (reads from `kv/data/seal/*` on kms.vyrn.ru)
- Automate Vault seeding via CI on value changes

## References

- ADR-005-v1 (rejected): SOPS + AGE (replaced by the current solution)
- apps/ARCHITECTURE.md — Section 3 (Vault Agent Injection, stage 2)
- TODO.md:117 — original mention of ESO (now being implemented)
- External Secrets Operator docs: https://external-secrets.io/latest/provider/hashicorp-vault/
