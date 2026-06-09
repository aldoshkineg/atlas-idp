# Vault Troubleshooting & Verification

## Symptoms

| Check        | Command                                                                              | Expected                                        |
| ------------ | ------------------------------------------------------------------------------------ | ----------------------------------------------- |
| Pod state    | `kubectl get pods -n vault`                                                          | vault-0 3/3 Running, vault-operator 1/1 Running |
| Vault status | `kubectl exec -n vault vault-0 -- vault status -address=http://127.0.0.1:8200`       | Initialized=true, Sealed=false                  |
| Gateway      | `curl -sk --resolve vault.atlas:443:127.0.0.1 https://vault.atlas:443/v1/sys/health` | JSON with initialized:true, sealed:false        |

## Known Issue: CrashLoopBackOff

### Cause

Stale `vault-unseal-keys` secret survives pod recreation. Bank-vaults sees existing keys and refuses to re-initialize.

### Fix

```bash
kubectl delete secret vault-unseal-keys -n vault
kubectl delete pod vault-0 -n vault --wait=false
```

Bank-vaults will re-initialize and generate fresh keys automatically.

## Config

- **Storage**: file (`/vault/file`) — ephemeral, no PVC. Data lost on pod restart.
- **TLS**: disabled (dev mode). Gateway terminates TLS.
- **Operator**: Bank-Vaults, deployed via Argo CD (`ghcr.io` OCI chart).
- **Unseal**: Shamir, 5 shares / 3 threshold. Keys stored in `vault-unseal-keys` secret.

## CLI Access

```bash
export VAULT_ADDR=https://vault.atlas:443
export VAULT_SKIP_VERIFY=true
# Login with root token from secret:
kubectl get secret vault-unseal-keys -n vault -o json | jq -r '.data["vault-root"]' | base64 -d
vault login <root-token>
```
