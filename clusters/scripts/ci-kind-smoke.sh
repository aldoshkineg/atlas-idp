#!/usr/bin/env bash
set -euo pipefail

export CLUSTER_NAME="${CLUSTER_NAME:-atlas-idp-ci}"

kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl cluster-info
kubectl get nodes

ready="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
if [[ "${ready}" -lt 1 ]]; then
  echo "ERROR: cluster is not Ready"
  exit 1
fi

echo "OK: kind cluster ${CLUSTER_NAME} is alive (${ready} node(s))"
