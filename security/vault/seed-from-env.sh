#!/usr/bin/env bash
set -euo pipefail

# Resolve .env + seed-mapping.conf and seed platform secrets into Vault.
# Usage: make vault-seed-from-env             (reads .env + mapping)
#   or:  unset VAULT_ADDR; ./seed-from-env.sh (relies on env vars already set)
# For each entry in seed-mapping.conf, resolves the ENV_VAR and writes it
# into a seed file, then delegates to seed-platform.sh (auto port-forwards).
# In CI the env vars come from GitHub secrets / action inputs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../..")"
ENV_FILE="$ROOT_DIR/.env"
MAPPING_FILE="$SCRIPT_DIR/seed-mapping.conf"

if [ ! -f "$MAPPING_FILE" ]; then
  echo "Missing mapping file: $MAPPING_FILE" >&2
  exit 1
fi

# Source .env if available (local dev). In CI env vars are already set.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

seed_file="$(mktemp)"
trap 'rm -f "$seed_file"' EXIT

while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  read -r vault_path pair <<< "$line"
  key="${pair%%=*}"
  var_name="${pair#*=}"

  if [ -z "$vault_path" ] || [ -z "$key" ] || [ -z "$var_name" ]; then
    echo "Invalid mapping line: $line" >&2
    exit 1
  fi

  value="${!var_name}"
  if [ -z "$value" ]; then
    echo "Missing env var '$var_name' for $vault_path $key" >&2
    exit 1
  fi

  echo "$vault_path $key=$value" >> "$seed_file"
done < "$MAPPING_FILE"

exec "$SCRIPT_DIR/seed-platform.sh" seed "$seed_file"
