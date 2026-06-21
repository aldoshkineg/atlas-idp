#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
GH_REPO="${GH_REPO:-}"

usage() {
  cat <<USAGE
Usage: ENV_FILE=/path/to/.env [GH_REPO=owner/repo] $0

Loads required GitHub Secrets from an env file and uploads them with gh:
  VAULT_TOKEN
  VL_MINIO_ROOT_USER
  VL_MINIO_ROOT_PASSWORD
  VL_REDIS_PASSWORD
USAGE
}

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  usage >&2
  exit 1
fi

required_secrets=(
  VAULT_TOKEN
  VL_MINIO_ROOT_USER
  VL_MINIO_ROOT_PASSWORD
  VL_REDIS_PASSWORD
  VL_GRAFANA_PASSWORD
)

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

gh_args=()
if [ -n "$GH_REPO" ]; then
  gh_args+=(--repo "$GH_REPO")
fi

for secret_name in "${required_secrets[@]}"; do
  value="${!secret_name:-}"

  if [ -z "$value" ]; then
    echo "$secret_name is empty or missing in $ENV_FILE" >&2
    exit 1
  fi

  printf '%s' "$value" | gh secret set "${gh_args[@]}" "$secret_name"
  echo "$secret_name uploaded"
done

echo "GitHub Secrets are ready"
