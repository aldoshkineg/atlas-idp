#!/usr/bin/env bash
# argocd-list — log in to ArgoCD and list applications, optionally by layer/project.
#
# Usage:
#   ./tools/argocd-list.sh [layer]
#
# layer maps to an ArgoCD project (base, security, storage, delivery,
# observability, workloads, ...). "all" (default) lists every application.
#
# Output is a condensed NAME / SYNC / HEALTH table.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we are logged in (fetches admin password and answers the prompt).
"$SCRIPT_DIR/argocd-login.sh" >/dev/null

LAYER="${1:-all}"

if [ "$LAYER" = "all" ]; then
  APPS="$(argocd app list -o json)"
else
  APPS="$(argocd app list --project "$LAYER" -o json)"
fi

format() {
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t'
  else
    cat
  fi
}

if command -v jq >/dev/null 2>&1; then
  echo "$APPS" | jq -r \
    '["NAME", "SYNC", "HEALTH"], (.[] | [.metadata.name, .status.sync.status, .status.health.status]) | @tsv' \
    | format
else
  # Fallback: full default listing if jq is unavailable.
  if [ "$LAYER" = "all" ]; then
    argocd app list
  else
    argocd app list --project "$LAYER"
  fi
fi
