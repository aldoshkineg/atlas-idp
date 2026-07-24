#!/usr/bin/env bash
set -euo pipefail

# Upload the entire .env as a single GitHub Secret (ENV_FILE). Every secret the
# platform needs (Vault seeds, root CA cert + key, etc.) lives in .env, so CI
# only ever has to fetch one secret and replay it.
#
# Requires: gh CLI, authenticated session, and a populated .env. Run
#           `make gh-seed` first so the CA cert/key + cosign key are embedded as base64.
#
# Usage:
#   make gh-seed                                # uploads repo-root .env
#   ENV_FILE=.env GH_REPO=owner/repo ./gh-seeds.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
GH_REPO="${GH_REPO:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

if ! grep -q '^ATLAS_CA_CRT_B64=' "$ENV_FILE"; then
  echo "ATLAS_CA_CRT_B64 missing in $ENV_FILE — embed the CA (see .env.example) and run 'make gh-seed' first" >&2
  exit 1
fi

gh_args=()
if [ -n "$GH_REPO" ]; then
  gh_args+=(--repo "$GH_REPO")
fi

gh secret set ENV_FILE "${gh_args[@]}" < "$ENV_FILE"
echo "GitHub Secret ENV_FILE uploaded from $ENV_FILE"
