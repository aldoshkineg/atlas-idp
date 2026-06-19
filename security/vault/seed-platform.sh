#!/usr/bin/env bash
set -euo pipefail

# Seed or update Vault KV entries from a path/key/value file.

MODE="${1:-}"
SEED_FILE="${2:-}"

usage() {
  echo "Usage: $0 {seed|update|verify} <secrets-file>" >&2
  echo "secrets-file format: '<vault-path> <key>=<value>'" >&2
}

if [ "$MODE" != "seed" ] && [ "$MODE" != "update" ] && [ "$MODE" != "verify" ]; then
  usage
  exit 1
fi

if [ -z "$SEED_FILE" ] || [ ! -f "$SEED_FILE" ]; then
  usage
  exit 1
fi

PF_PID=""

cleanup() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

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

put_secret() {
  local path="$1"
  local key="$2"
  local value="$3"

  vault kv patch "$path" "$key=$value" >/dev/null
}

verify_secret() {
  local path="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(vault kv get -field="$key" "$path" 2>/dev/null)" || {
    echo "Vault key '$path' is missing '$key'" >&2
    return 1
  }

  if [ "$actual" != "$expected" ]; then
    echo "Vault key '$path' field '$key' does not match expected value" >&2
    return 1
  fi

  echo "Vault key '$path' field '$key' matches"
}

entries=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  [ -n "$line" ] || continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  read -r secret_path pair <<< "$line"
  key="${pair%%=*}"
  value="${pair#*=}"

  if [[ "$line" != *" "* ]] || [[ "$pair" != *"="* ]]; then
    echo "Invalid secrets-file line: $line" >&2
    exit 1
  fi

  if [ -z "$secret_path" ] || [ -z "$key" ] || [ -z "$value" ]; then
    echo "Invalid secrets-file line: $line" >&2
    exit 1
  fi

  entries=$((entries + 1))

  if [ "$MODE" = "verify" ]; then
    verify_secret "$secret_path" "$key" "$value"
    continue
  fi

  put_secret "$secret_path" "$key" "$value"
  verify_secret "$secret_path" "$key" "$value"
done < "$SEED_FILE"

if [ "$entries" -eq 0 ]; then
  echo "secrets-file is empty: $SEED_FILE" >&2
  exit 1
fi

echo "Vault platform secrets are ready"
