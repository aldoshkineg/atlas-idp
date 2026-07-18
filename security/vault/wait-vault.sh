#!/usr/bin/env bash
set -euo pipefail

# Wait until the local Vault instance is ready for seeding.
# Usage: ./wait-vault.sh
# Called automatically by CI (.github/actions/vault-seeds) before seeding.
# Requires: kubectl, a running cluster with Vault, and VAULT_ADDR reachable
# (provided by the act-runner port-forward). Falls back to kubectl exec only
# when VAULT_ADDR is not reachable.

VAULT_WAIT_TOTAL_TIMEOUT="${VAULT_WAIT_TOTAL_TIMEOUT:-600}"
VAULT_WAIT_POD_READY_TIMEOUT="${VAULT_WAIT_POD_READY_TIMEOUT:-420}"
VAULT_WAIT_KV_TIMEOUT="${VAULT_WAIT_KV_TIMEOUT:-120}"
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

kubectl -n vault wait pod/vault-0 --for=condition=Ready --timeout="${VAULT_WAIT_POD_READY_TIMEOUT}s"

# Prefer the already-established port-forward (VAULT_ADDR); fall back to exec.
if [ -n "${VAULT_ADDR:-}" ] && vault status >/dev/null 2>&1; then
  echo "Vault API reachable via VAULT_ADDR ($VAULT_ADDR)"
else
  echo "Waiting for KV engine at secret/ via kubectl exec..."
  VAULT_ROOT="$(kubectl -n vault get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)"
  kv_deadline=$((SECONDS + VAULT_WAIT_KV_TIMEOUT))
  until kubectl -n vault exec vault-0 -c vault -- env VAULT_TOKEN="$VAULT_ROOT" vault secrets list -address=http://127.0.0.1:8200 -format=json 2>/dev/null | grep -q '"secret/"'; do
    [ "$((kv_deadline - SECONDS))" -le 0 ] && echo "Timed out waiting for KV engine" >&2 && exit 1
    sleep 2
  done
fi

echo "Vault API is ready"
