#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${KIND_CONFIG:-${ROOT}/clusters/kind/cluster.yaml}"
CLUSTER_NAME="${CLUSTER_NAME:-atlas-idp}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists"
  exit 0
fi

kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG}"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
