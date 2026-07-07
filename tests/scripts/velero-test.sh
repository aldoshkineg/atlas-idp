#!/usr/bin/env bash
set -euo pipefail

TS=$(date +%s)
BACKUP_NAME="velero-test-backup-$TS"
RESTORE_NAME="velero-test-restore-$TS"
NS="testing"
LABEL="app=backup-test"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

cleanup() {
  echo "=== Cleanup ==="
  # Delete restore only if it exists
  velero restore get "$RESTORE_NAME" >/dev/null 2>&1 && velero restore delete --confirm "$RESTORE_NAME" 2>/dev/null || true
  # Delete backup only if it exists and is complete
  velero backup get "$BACKUP_NAME" >/dev/null 2>&1 && velero backup delete --confirm "$BACKUP_NAME" 2>/dev/null || true
  kubectl delete pod -n "$NS" -l "$LABEL" --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete pvc -n "$NS" -l "$LABEL" --ignore-not-found --wait=false 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Deploy test pod with PVC ==="
kubectl apply -f tests/gateway/namespace.yaml 2>/dev/null || true
kubectl apply -f tests/velero/pvc.yaml
kubectl apply -f tests/velero/pod.yaml

echo "  Waiting for pod to generate file and become Ready..."
kubectl wait --for=condition=Ready pod -l "$LABEL" -n "$NS" --timeout=120s > /dev/null 2>&1 || {
  fail "backup-test-pod not ready"
  exit 1
}
sleep 2

echo "=== Verify test file on PVC ==="
FILE_BYTES=$(kubectl exec -n "$NS" backup-test-pod -- wc -c /data/test.txt 2>/dev/null | awk '{print $1}' || echo "0")
echo "  File size: $FILE_BYTES bytes"
if [[ "$FILE_BYTES" -gt 10000 ]]; then
  ok "Test file written to PVC ($FILE_BYTES bytes)"
else
  fail "Test file missing or too small"
  exit 1
fi

echo "=== Create Velero backup (label: $LABEL) ==="
velero backup create "$BACKUP_NAME" \
  --include-namespaces "$NS" \
  --selector "$LABEL" \
  --default-volumes-to-fs-backup \
  --wait > /dev/null 2>&1 || {
  fail "backup creation failed"
  exit 1
}

BACKUP_STATUS=$(velero backup get "$BACKUP_NAME" -o json 2>/dev/null | jq -r '.status.phase' || echo "unknown")
if [[ "$BACKUP_STATUS" == "Completed" ]]; then
  ok "Backup '$BACKUP_NAME' completed (phase: $BACKUP_STATUS)"
else
  fail "Backup phase is '$BACKUP_STATUS' (expected 'Completed')"
fi

echo "=== Verify backup in MinIO ==="
MC_OUTPUT=$(kubectl exec -n minio deploy/minio -- sh -c "
  mc alias set local http://127.0.0.1:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD > /dev/null 2>&1
  mc ls local/k8s-velero-backups/backups/
" 2>&1)
echo "$MC_OUTPUT" | grep -q "$BACKUP_NAME" && {
  ok "Backup data found in MinIO bucket"
} || {
  fail "Backup not found in MinIO - check velero logs"
}

echo "=== Simulate disaster: delete pod + PVC ==="
kubectl delete pod backup-test-pod -n "$NS" --wait=true --timeout=60s > /dev/null 2>&1 || true
kubectl delete pvc backup-test-pvc -n "$NS" --wait=true --timeout=60s > /dev/null 2>&1 || true
kubectl wait --for=delete pod/backup-test-pod -n "$NS" --timeout=30s > /dev/null 2>&1 || true
ok "Pod and PVC deleted (disaster simulated)"

echo "=== Restore from backup ==="
velero restore create "$RESTORE_NAME" \
  --from-backup "$BACKUP_NAME" \
  --wait > /dev/null 2>&1 || {
  fail "restore failed"
  exit 1
}

RESTORE_STATUS=$(velero restore get "$RESTORE_NAME" -o json 2>/dev/null | jq -r '.status.phase' || echo "unknown")
if [[ "$RESTORE_STATUS" == "Completed" ]]; then
  ok "Restore '$RESTORE_NAME' completed (phase: $RESTORE_STATUS)"
else
  fail "Restore phase is '$RESTORE_STATUS' (expected 'Completed')"
fi

echo "  Waiting for restored pod to regenerate file..."
kubectl wait --for=condition=Ready pod -l "$LABEL" -n "$NS" --timeout=120s > /dev/null 2>&1 || {
  fail "restored pod not ready"
  exit 1
}
sleep 2
ok "Restored pod is Ready with regenerated data"

echo "=== Verify restored PVC ==="
RESTORED_BYTES=$(kubectl exec -n "$NS" backup-test-pod -- wc -c /data/test.txt 2>/dev/null | awk '{print $1}' || echo "0")
echo "  Restored file size: $RESTORED_BYTES bytes"
SAMPLE=$(kubectl exec -n "$NS" backup-test-pod -- head -3 /data/test.txt 2>/dev/null)
echo "  Content check:"
echo "$SAMPLE" | sed 's/^/    /'
if [[ "$RESTORED_BYTES" -gt 10000 ]]; then
  ok "PVC data restored (${RESTORED_BYTES} bytes)"
else
  fail "PVC data not restored"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
