#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

if [ "$MODE" != "seed" ] && [ "$MODE" != "update" ]; then
  echo "Usage: $0 {seed|update}" >&2
  exit 1
fi

require_env() {
  local name="$1"

  if [ -z "${!name:-}" ]; then
    echo "$name is required" >&2
    exit 1
  fi
}

require_env VL_MINIO_ROOT_USER
require_env VL_MINIO_ROOT_PASSWORD
require_env VL_REDIS_PASSWORD

PF_PID=""

cleanup() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ -z "${VAULT_ADDR:-}" ]; then
  export VAULT_ADDR="http://127.0.0.1:8200"

  kubectl -n vault port-forward svc/vault 8200:8200 >/tmp/atlas-idp-vault-port-forward.log 2>&1 &
  PF_PID="$!"

  for _ in $(seq 1 30); do
    if vault status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

export VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN is required}"

put_if_missing() {
  local key="$1"
  shift

  if vault kv get "$key" >/dev/null 2>&1; then
    echo "Vault key '$key' already exists; skipping seed"
    return 0
  fi

  vault kv put "$key" "$@"
}

put_update() {
  local key="$1"
  shift

  vault kv put "$key" "$@"
}

if [ "$MODE" = "seed" ]; then
  put_if_missing secret/platform/minio \
    rootUser="${VL_MINIO_ROOT_USER}" \
    rootPassword="${VL_MINIO_ROOT_PASSWORD}"

  put_if_missing secret/platform/redis \
    redis-password="${VL_REDIS_PASSWORD}"
else
  put_update secret/platform/minio \
    rootUser="${VL_MINIO_ROOT_USER}" \
    rootPassword="${VL_MINIO_ROOT_PASSWORD}"

  put_update secret/platform/redis \
    redis-password="${VL_REDIS_PASSWORD}"
fi

echo "Vault platform secrets are ready"
