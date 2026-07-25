#!/usr/bin/env bash
set -euo pipefail

# Apply/remove platform RBAC policies (ClusterRoles, bindings).
#
# Usage:
#   rbac.sh {apply|delete}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RBAC_DIR="${ROOT_DIR}/security/rbac"

[ -d "$RBAC_DIR" ] || { echo "ERROR: RBAC dir not found: $RBAC_DIR" >&2; exit 1; }

case "${1:-}" in
  apply)  kubectl apply -f "$RBAC_DIR/" ;;
  delete) kubectl delete -f "$RBAC_DIR/" --ignore-not-found ;;
  *) echo "Usage: rbac.sh {apply|delete}" >&2; exit 1 ;;
esac
