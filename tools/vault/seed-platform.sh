#!/usr/bin/env bash
set -euo pipefail

# Seed or update Vault KV entries from a path/key/value file.
#
# Reads a secrets file in format: '<vault-path> <key>=<value>'
# For each line it writes/patches the key in Vault KV at the given path.
# Modes:
#   seed   — create or update entries, then verify
#   update — same as seed (patch existing or create new)
#   verify — check that stored values match the file
#
# Automatically resolves VAULT_TOKEN from the cluster secret vault-unseal-keys
# if VAULT_ADDR is not set. Port-forwards to vault service if needed.
# Usage:
#   ./seed-platform.sh seed /path/to/secrets-file
#   ./seed-platform.sh verify /path/to/secrets-file
# Secrets file format:
#   secret/platform/myapp  key1=value1
#   secret/platform/myapp  key2=value2

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

  for _ in $(seq 1 10); do
    if vault status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
else
  echo "Reusing existing VAULT_ADDR=$VAULT_ADDR"
fi

put_secret() {
  local path="$1"
  shift
  local pairs=("$@")

  if vault kv get "$path" >/dev/null 2>&1; then
    vault kv patch "$path" "${pairs[@]}" >/dev/null
  else
    vault kv put "$path" "${pairs[@]}" >/dev/null
  fi
}

get_field() {
  local path="$1"
  local key="$2"
  vault kv get -field="$key" "$path" 2>/dev/null
}

# Compare desired pairs against Vault; returns 0 if all match, 1 otherwise.
path_matches() {
  local path="$1"
  shift
  local pairs=("$@")
  local pair key value actual

  for pair in "${pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    actual="$(get_field "$path" "$key")"
    [ "$actual" = "$value" ] || return 1
  done
  return 0
}

verify_path() {
  local path="$1"
  shift
  local pairs=("$@")
  local pair key value actual

  for pair in "${pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    actual="$(get_field "$path" "$key")" || {
      echo "Vault key '$path' is missing '$key'" >&2
      return 1
    }
    if [ "$actual" != "$value" ]; then
      echo "Vault key '$path' field '$key' does not match expected value" >&2
      return 1
    fi
    echo "Vault key '$path' field '$key' matches"
  done
}

entries=0
declare -A path_pairs=()
declare -a path_order=()

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

  if [ -z "${path_pairs[$secret_path]:-}" ]; then
    path_order+=("$secret_path")
  fi
  path_pairs[$secret_path]+=" $key=$value"
done < "$SEED_FILE"

if [ "$entries" -eq 0 ]; then
  echo "secrets-file is empty: $SEED_FILE" >&2
  exit 1
fi

for secret_path in "${path_order[@]}"; do
  # Values are simple key=value pairs without spaces; word-splitting is safe here.
  # shellcheck disable=SC2206
  pairs=(${path_pairs[$secret_path]})

  if [ "$MODE" = "verify" ]; then
    verify_path "$secret_path" "${pairs[@]}"
    continue
  fi

  if path_matches "$secret_path" "${pairs[@]}"; then
    echo "Vault path '$secret_path' already up to date, skipping"
    continue
  fi

  put_secret "$secret_path" "${pairs[@]}"
  verify_path "$secret_path" "${pairs[@]}"
done

echo "Vault platform secrets are ready"
