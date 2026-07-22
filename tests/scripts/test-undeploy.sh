#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

KUBECTL="${KUBECTL:-kubectl}"

# force_delete_ns NAME
# Delete a namespace and, if it gets wedged in Terminating (e.g. a CNPG
# cluster whose graceful shutdown cannot reach MinIO), force-finalize it
# directly through the API so the command never hangs.
force_delete_ns() {
  local ns="$1"
  if ! $KUBECTL get ns "$ns" >/dev/null 2>&1; then
    return 0
  fi

  $KUBECTL delete ns "$ns" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

  if $KUBECTL get ns "$ns" >/dev/null 2>&1; then
    echo "  namespace $ns stuck Terminating; force-finalizing via API"
    $KUBECTL proxy --port=8001 >/tmp/kubeproxy-undeploy.log 2>&1 &
    local pid=$!
    sleep 4
    $KUBECTL get ns "$ns" -o json 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); d.setdefault('spec',{})['finalizers']=[]; print(json.dumps(d))" \
      > /tmp/ns-finalize.json
    curl -s -k -X PUT -H "Content-Type: application/json" \
      --data-binary @/tmp/ns-finalize.json "http://localhost:8001/api/v1/namespaces/$ns/finalize" >/dev/null 2>&1 || true
    kill "$pid" 2>/dev/null || true
  fi
  echo "  removed namespace $ns"
}

echo "=== Remove test resources ==="
$KUBECTL delete -f tests/keda --ignore-not-found 2>/dev/null || true
$KUBECTL delete -f tests/vault --ignore-not-found 2>/dev/null || true
$KUBECTL delete -f tests/gateway --ignore-not-found 2>/dev/null || true
$KUBECTL delete -f tests/network-policy --ignore-not-found 2>/dev/null || true

# Re-apply the minio CNP so CNPG can reach MinIO for a graceful shutdown.
# The db-backup test removes this CNP in its own cleanup, leaving the CNPG
# clusters (and the namespace) behind; without it, deletion hangs forever.
echo "=== Restore MinIO access for CNPG graceful shutdown ==="
$KUBECTL apply -f tests/db-backup/minio-access.yaml --ignore-not-found 2>/dev/null || true

echo "=== Remove db-backup test namespace ==="
force_delete_ns db-backup-test

# Remove the temporary minio CNP created above.
$KUBECTL delete cnp -n minio db-backup-test-minio-access --ignore-not-found 2>/dev/null || true

echo "=== Remove remaining test namespaces ==="
$KUBECTL delete pod -n seal seal-test --ignore-not-found 2>/dev/null || true
$KUBECTL delete pod -n testing -l app=backup-test --ignore-not-found 2>/dev/null || true
$KUBECTL delete pvc -n testing -l app=backup-test --ignore-not-found 2>/dev/null || true
force_delete_ns argocd-rollout-test
force_delete_ns keda-test
force_delete_ns netpol-test
force_delete_ns testing

$KUBECTL delete sc csi-hostpath-sc --ignore-not-found 2>/dev/null || true

echo "=== Done ==="
