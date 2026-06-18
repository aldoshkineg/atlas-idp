#!/usr/bin/env bash
set -euo pipefail

# Create the Kubernetes Secret consumed by External Secrets Operator.

resolve_vault_token() {
  if [ -z "${VAULT_ADDR:-}" ] && command -v kubectl >/dev/null 2>&1 && kubectl -n vault get secret vault-unseal-keys >/dev/null 2>&1; then
    VAULT_TOKEN="$(kubectl -n vault get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)"
    export VAULT_TOKEN
    echo "Using Vault root token from vault-unseal-keys"
    return 0
  fi

  if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "VAULT_TOKEN is required" >&2
    exit 1
  fi
}

resolve_vault_token

kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token="${VAULT_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ESO Vault token Secret is ready in namespace external-secrets"
