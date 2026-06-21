#!/usr/bin/env bash
set -euo pipefail

# Wait until the local Kind Vault instance is ready for seeding.
# Usage: ./wait-vault.sh
# Called automatically by CI (.github/actions/vault-seeds) before seeding.
# Requires: kubectl, a running kind cluster with Vault CR applied.

VAULT_WAIT_TOTAL_TIMEOUT="${VAULT_WAIT_TOTAL_TIMEOUT:-60}"
deadline=$((SECONDS + VAULT_WAIT_TOTAL_TIMEOUT))

remaining() { echo $((deadline - SECONDS)); }

echo "Waiting for Vault namespace (budget ${VAULT_WAIT_TOTAL_TIMEOUT}s)..."
until kubectl get namespace vault &>/dev/null; do
  [ "$(remaining)" -le 0 ] && echo "Timed out waiting for Vault namespace" >&2 && exit 1
  sleep 2
done

echo "Waiting for pod vault-0 in namespace vault..."
until kubectl -n vault get pod vault-0 &>/dev/null; do
  [ "$(remaining)" -le 0 ] && echo "Timed out waiting for vault-0 pod" >&2 && exit 1
  sleep 2
done

kubectl -n vault wait pod/vault-0 --for=condition=Ready --timeout="$(remaining)s"

kubectl -n vault exec vault-0 -c vault -- vault status -address=http://127.0.0.1:8200 >/dev/null

echo "Waiting for KV engine at secret/ to be enabled..."
VAULT_ROOT="$(kubectl -n vault get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)"
until kubectl -n vault exec vault-0 -c vault -- env VAULT_TOKEN="$VAULT_ROOT" vault secrets list -address=http://127.0.0.1:8200 -format=json 2>/dev/null | grep -q '"secret/"'; do
  [ "$(remaining)" -le 0 ] && echo "Timed out waiting for KV engine" >&2 && exit 1
  sleep 2
done

echo "Vault API is ready"
