#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLUSTER_NAME="${CLUSTER_NAME:-atlas-idp-ci}"
export KIND_CONFIG="${KIND_CONFIG:-${ROOT}/clusters/kind/cluster-ci.yaml}"

"${ROOT}/clusters/scripts/ci-install-tools.sh"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
fi

"${ROOT}/clusters/scripts/create-cluster.sh"
kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
