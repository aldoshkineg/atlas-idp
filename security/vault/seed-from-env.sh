#!/usr/bin/env bash
set -euo pipefail

# Resolve .env + seed-mapping.conf and seed platform + workload secrets into Vault.
# Usage: make vault-seed-from-env             (reads .env + all mappings)
#   or:  unset VAULT_ADDR; ./seed-from-env.sh (relies on env vars already set)
# For each entry in ALL seed-mapping.conf files (platform + workloads), resolves
# the ENV_VAR and writes it into a seed file, then delegates to seed-platform.sh.
# In CI the env vars come from GitHub secrets / action inputs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../..")"
ENV_FILE="$ROOT_DIR/.env"
PLATFORM_MAPPING="$SCRIPT_DIR/seed-mapping.conf"

# Source .env if available (local dev). In CI env vars are already set.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

seed_file="$(mktemp)"
trap 'rm -f "$seed_file"' EXIT

process_mapping() {
  local mapping_file="$1"
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    read -r vault_path pair <<< "$line"
    key="${pair%%=*}"
    var_name="${pair#*=}"

    if [ -z "$vault_path" ] || [ -z "$key" ] || [ -z "$var_name" ]; then
      echo "Invalid mapping line in $mapping_file: $line" >&2
      exit 1
    fi

    value="${!var_name}"
    if [ -z "$value" ]; then
      echo "Missing env var '$var_name' for $vault_path $key (from $mapping_file)" >&2
      exit 1
    fi

    echo "$vault_path $key=$value" >> "$seed_file"
  done < "$mapping_file"
}

# Process platform-level mapping
if [ -f "$PLATFORM_MAPPING" ]; then
  echo "Processing platform mapping: $PLATFORM_MAPPING"
  process_mapping "$PLATFORM_MAPPING"
else
  echo "Warning: platform mapping not found: $PLATFORM_MAPPING (skipping)"
fi

exec "$SCRIPT_DIR/seed-platform.sh" seed "$seed_file"
