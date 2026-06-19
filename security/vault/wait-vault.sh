#!/usr/bin/env bash
set -euo pipefail

# Wait until the local Kind Vault instance is ready for seeding.

VAULT_WAIT_TOTAL_TIMEOUT="${VAULT_WAIT_TOTAL_TIMEOUT:-60}"
deadline=$((SECONDS + VAULT_WAIT_TOTAL_TIMEOUT))

remaining() { echo $((deadline - SECONDS)); }

echo "Waiting for Vault namespace (budget ${VAULT_WAIT_TOTAL_TIMEOUT}s)..."
until kubectl get namespace vault &>/dev/null; do
  [ "$(remaining)" -le 0 ] && echo "Timed out waiting for Vault namespace" >&2 && exit 1
  sleep 2
done

kubectl -n vault wait pod/vault-0 --for=condition=Ready --timeout="$(remaining)s"

kubectl -n vault exec vault-0 -c vault -- vault status -address=http://127.0.0.1:8200 >/dev/null

echo "Vault API is ready"
