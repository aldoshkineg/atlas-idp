# Vault & Secrets Management

How secrets work on the platform: an in-cluster HashiCorp Vault (managed by the
Bank-Vaults operator) is the single secret store; External Secrets Operator (ESO)
projects Vault data into Kubernetes `Secret`s. Nothing sensitive is committed to git.

## Components

| Component             | App manifest                               | Chart / version                              | Namespace          | Wave |
| --------------------- | ------------------------------------------ | -------------------------------------------- | ------------------ | ---- |
| vault-operator        | `gitops/platform/base/vault-operator.yaml` | bank-vaults `vault-operator` 1.24.0          | `vault`            | 2    |
| vault-secrets-webhook | `.../base/vault-secrets-webhook.yaml`      | bank-vaults `secrets-webhook` 0.4.1          | `vault`            | 3    |
| external-secrets      | `.../base/external-secrets.yaml`           | `external-secrets` 0.14.0                    | `external-secrets` | 3    |
| platform-secrets      | `.../base/platform-secrets.yaml`           | raw manifests (`resources/platform-secrets`) | multiple           | 4    |

The Vault instance itself is a `Vault` CR: `gitops/platform/base/resources/vault/vault-cr.yaml`.

## Our configuration

- **Single replica** (`size: 1`), image `hashicorp/vault:1.18.0`, UI enabled.
- **Storage:** `file` backend on a 256Mi PVC (`linstor-replicated`) — replicated at the
  block layer by DRBD, not by Vault HA.
- **TLS disabled in-cluster** (`tls_disable: true`); external access is TLS-terminated by
  the Cilium Gateway at `https://vault.atlas` (route: `gitops/platform/base/resources/gateway-routes/vault.yaml`).
- **Unseal:** Bank-Vaults auto-unseal via the Kubernetes secret `vault-unseal-keys` (ns `vault`).
  The secret is created at first init; if it goes stale, see
  [`runbooks/vault-troubleshooting.md`](runbooks/vault-troubleshooting.md).
- **Auth & policy:** Kubernetes auth is enabled; policy `platform-read` grants read/list on
  `secret/data/platform/*`. KV v2 engine mounted at `secret/` (`max_versions: 10`).

## Secret flow

```
.env (operator machine, git-ignored)
  │ tools/vault/seed-vault.sh          (CI: seed-vault action in ci-base)
  ▼
Vault KV  secret/platform/{minio,redis,grafana}
  │ ClusterSecretStore "vault"          (ESO, token from vault-unseal-keys)
  ▼
ExternalSecret → Kubernetes Secret      (refreshInterval: 1m)
  │
  ▼
Helm charts reference existingSecret    (minio-auth, redis-auth, grafana-admin, velero-aws, production-db-backup)
```

Platform `ExternalSecret`s live in `gitops/platform/base/resources/platform-secrets/`:

| ExternalSecret         | Target ns : Secret                  | Vault key                 |
| ---------------------- | ----------------------------------- | ------------------------- |
| `minio-auth`           | `minio` : `minio-auth`              | `secret/platform/minio`   |
| `redis-auth`           | `redis` : `redis-auth`              | `secret/platform/redis`   |
| `grafana-admin`        | `monitoring` : `grafana-admin`      | `secret/platform/grafana` |
| `velero-aws`           | `velero` : `velero-aws`             | `secret/platform/minio`   |
| `production-db-backup` | `database` : `production-db-backup` | `secret/platform/minio`   |

Workload secrets follow the same pattern but under `secret/workloads/<group>/<app>/`,
seeded by `atlasctl seed` — see [`workloads.md`](workloads.md).

## Seeding

`tools/vault/` contains the seeding toolchain:

- `seed-mapping.conf` — declarative map of Vault path → env var (from `.env`).
- `seed-vault.sh` / `seed-platform.sh` — idempotent `seed | update | verify`; auto
  port-forwards and resolves the root token from `vault-unseal-keys`.
- `wait-vault.sh` — CI gate: waits for the pod, then the KV engine.

In CI the `seed-vault` composite action runs during the **base** stage right after
Terraform apply. Locally: `make seed-vault`.

## Real usage

```bash
make test-vault        # e2e: writes a test KV, injects it into a pod via
                       # vault-agent annotations (role platform-read), asserts the value
vault kv get secret/platform/minio        # via `kubectl port-forward svc/vault 8200` + root token
```

The e2e test (`tests/vault/`, `tests/scripts/vault-test.sh`) also exercises the
Kubernetes auth path end to end, so a green `test-vault` proves: pod → k8s auth →
policy → KV read → template render.

## Known limitations

- Single replica with `file` storage — restart-safe (PVC) but not Vault-HA.
- ESO authenticates with the **root token**; a scoped token is a pending hardening step.
- Init/unseal bootstrap is a one-time manual step before the first `seed-vault` (see
  [`setup.md`](setup.md)).

## See also

- [`runbooks/vault-troubleshooting.md`](runbooks/vault-troubleshooting.md)
- [`gitops.md`](gitops.md) — layer ordering and sync waves
