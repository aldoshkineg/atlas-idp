#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper around Terraform for infra/environments/<ENV>.
#
# Usage:
#   infra.sh {init|plan|apply} [ENV]
#
# Environment:
#   ENV                 Target environment (default: stage)
#   TF_PLUGIN_CACHE_DIR Terraform plugin cache (default: /var/tmp/atlas/act_cache/tf)
#   TF_STATE_DIR        Local state dir        (default: /var/tmp/atlas/terraform)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CMD="${1:-apply}"
ENV="${2:-stage}"

TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/var/tmp/atlas/act_cache/tf}"
TF_STATE_DIR="${TF_STATE_DIR:-/var/tmp/atlas/terraform}"

ENV_DIR="${ROOT_DIR}/infra/environments/${ENV}"

[ -d "$ENV_DIR" ] || { echo "ERROR: environment dir not found: $ENV_DIR" >&2; exit 1; }

mkdir -p "$TF_PLUGIN_CACHE_DIR" "$TF_STATE_DIR"
export TF_PLUGIN_CACHE_DIR

case "$CMD" in
  init)  ( cd "$ENV_DIR" && terraform init ) ;;
  plan)  ( cd "$ENV_DIR" && terraform plan ) ;;
  apply) ( cd "$ENV_DIR" && terraform init && terraform apply -auto-approve ) ;;
  *) echo "Unknown command: $CMD (use init|plan|apply)" >&2; exit 1 ;;
esac
