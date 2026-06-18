# Vault / External Secrets migration progress

## Completed

- Vault CLI tooling is available for GitHub Actions.
- Vault helper scripts live under `security/vault/`.
- External Secrets Operator is added to the platform-kind security layer.
- MinIO and Redis now use ExternalSecret resources instead of legacy sealed secret CRs.
- Legacy secret encryption Application and manifests were removed from platform-kind.
- ArgoCD dependencies now point to `external-secrets` instead of the legacy secret encryption controller.
- Local validation completed: shell syntax, Trivy config, Terraform validate, `git diff --check`; `yamllint` exits cleanly with an existing warning in `security/rbac/workload-deployer.yaml:63`.
- CI Vault seeding is moved into reusable `.github/actions/vault-seeds`, using `KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/kind}"`.
- `security/vault/gh-seeds.sh` can upload required GitHub Secrets from `.env`.

## Runtime flow

1. GitHub CI installs `vault` CLI.
2. Terraform creates the kind cluster and ArgoCD.
3. CI waits for Vault.
4. CI creates `external-secrets/vault-token` from `VAULT_TOKEN`.
5. CI runs `./security/vault/seed-platform.sh seed <secrets-file>`.
6. ArgoCD syncs External Secrets Operator, ClusterSecretStore, ExternalSecrets, MinIO and Redis.

## Verification commands

```bash
kubectl get externalsecret -A
kubectl get secret minio-auth -n minio
kubectl get secret redis-auth -n redis
vault kv get secret/platform/minio
vault kv get secret/platform/redis
```

## Update flow

```bash
VAULT_TOKEN=... ./security/vault/update-platform.sh update <secrets-file>
```

The update script writes Vault values and restarts:

- `statefulset/minio` in namespace `minio`
- `statefulset/redis-master` in namespace `redis`
