#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLUSTER_NAME="${CLUSTER_NAME:-atlas-idp-ci}"

if command -v kind >/dev/null 2>&1; then
  :
elif [[ -x "${ROOT}/clusters/scripts/ci-install-tools.sh" ]]; then
  "${ROOT}/clusters/scripts/ci-install-tools.sh"
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Deleted cluster ${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' not found, nothing to delete"
fi

rm -rf "${CI_PROJECT_DIR:-${ROOT}}/kind-kubeconfig" 2>/dev/null || true
