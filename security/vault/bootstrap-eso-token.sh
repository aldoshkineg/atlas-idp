#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_TOKEN is required" >&2
  exit 1
fi

kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token="${VAULT_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ESO Vault token Secret is ready in namespace external-secrets"
