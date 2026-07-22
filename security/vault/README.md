# Vault Scripts — Local & CI

Tools for seeding and updating platform secrets in the in-cluster Vault (Bank-Vaults),
and bootstrapping External Secrets Operator (ESO).

## Architecture

```
.env (local) or GitHub Secrets (CI)
        │
        ▼
seed-mapping.conf ──► seed-from-env.sh ──► seed-platform.sh ──► Vault (KV)
                           ▲                                        │
                           │                                        ▼
                    wait-vault.sh                      External Secrets Operator
                    bootstrap-eso-token.sh                   │
                                                             ▼
                                                     K8s Secrets
```

- **Local dev**: `make vault-seed-from-env` reads `.env` + `seed-mapping.conf`, seeds Vault
- **CI**: GitHub Actions passes secrets as env vars via `inputs`, action calls `seed-from-env.sh` (no `.env`)
- **ESO** auto-syncs Vault changes to Kubernetes Secrets — no manual restarts needed

## Scripts

| Script                   | Purpose                                                                                        | Used by                               |
| ------------------------ | ---------------------------------------------------------------------------------------------- | ------------------------------------- |
| `seed-platform.sh`       | Core: read secrets file, write/patch/verify entries in Vault KV                                | CI (`vault-seeds`), direct invocation |
| `seed-from-env.sh`       | Resolve env vars (from `.env` or already set) via `seed-mapping.conf`, call `seed-platform.sh` | `make vault-seed-from-env`, CI        |
| `seed-mapping.conf`      | Mapping: `vault-path key=ENV_VAR_NAME`                                                         | `seed-from-env.sh`                    |
| `wait-vault.sh`          | Wait for Vault namespace, pod readiness, KV engine availability                                | CI (`vault-seeds`)                    |
| `bootstrap-eso-token.sh` | Create `external-secrets/vault-token` Secret from `vault-unseal-keys`                          | CI (`vault-seeds`)                    |
| `gh-seeds.sh`            | Upload `.env` vars to GitHub Secrets via `gh` CLI                                              | Manual CI bootstrap                   |

## Usage

### Local dev — seed all platform secrets

```bash
make vault-seed-from-env
```

Reads `.env` + `seed-mapping.conf`. Auto port-forwards to `vault-0` via `kubectl`.
Skips `.env` if absent (CI mode).

### Direct seed with custom values

```bash
# Create a secrets file (format: <vault-path> <key>=<value>)
cat > /tmp/secrets.txt <<EOF
secret/platform/myapp apiKey=supersecret
secret/platform/myapp dbPassword=dbpass123
EOF

# Seed into Vault
./security/vault/seed-platform.sh seed /tmp/secrets.txt
```

### Verify that Vault values match a file

```bash
./security/vault/seed-platform.sh verify /tmp/secrets.txt
```

### Manual seed without port-forward (use external Vault addr)

```bash
VAULT_ADDR=https://vault.example.com VAULT_TOKEN=s.tok ./security/vault/seed-platform.sh seed /tmp/secrets.txt
```

### Upload local env vars to GitHub Secrets

```bash
ENV_FILE=.env GH_REPO=owner/repo ./security/vault/gh-seeds.sh
```

Uploads `VL_MINIO_ROOT_USER`, `VL_MINIO_ROOT_PASSWORD`,
`VL_REDIS_PASSWORD`, `VL_GRAFANA_PASSWORD` to the specified repo.

## CI pipeline flow

In `.github/workflows/ci-base.yaml`, the `vault-seeds` step:

1. Sets `VL_*` env vars from GitHub Secrets (`inputs`)
2. Resolves `VAULT_TOKEN` from in-cluster `vault-unseal-keys`
3. Calls `wait-vault.sh` — waits up to 600s for Vault readiness
4. Calls `bootstrap-eso-token.sh` — creates ESO token Secret
5. Calls `seed-from-env.sh` — reads `seed-mapping.conf`, resolves `VL_*` vars, seeds Vault

No hardcoded paths or inline secrets — all mapping is in `seed-mapping.conf`.

## Adding a new platform secret

1. Add the variable to `.env` (prefix `VL_`):

   ```env
   VL_MYAPP_KEY=myvalue
   ```

2. Add mapping to `seed-mapping.conf`:

   ```
   secret/platform/myapp apiKey=VL_MYAPP_KEY
   ```

3. Run locally to test:

   ```bash
   make vault-seed-from-env
   ```

4. Add `ExternalSecret` manifest in `gitops/platform-kind/layers/security/resources/platform-secrets/`

5. Add the new secret to GitHub repo Secrets with the same name (`VL_MYAPP_KEY`)

6. Commit and push — CI will seed + ArgoCD + ESO will sync automatically
