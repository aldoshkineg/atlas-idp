#!/usr/bin/env bash
set -euo pipefail

NS="db-backup-test"
CLUSTER_SRC="test-db-source"
CLUSTER_RECOVERY="test-db-recovery"
BACKUP_NAME="test-db-backup"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

cleanup() {
  # Remove the temporary MinIO ingress allow for this test's namespace so the
  # production platform-ingress policy is never widened permanently.
  kubectl delete -f tests/db-backup/minio-access.yaml --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Read MinIO credentials from cluster ==="
MINIO_ROOT_USER=$(kubectl -n minio get secret minio-auth -o jsonpath='{.data.rootUser}' 2>/dev/null | base64 -d)
MINIO_ROOT_PASSWORD=$(kubectl -n minio get secret minio-auth -o jsonpath='{.data.rootPassword}' 2>/dev/null | base64 -d)
if [ -z "$MINIO_ROOT_USER" ] || [ -z "$MINIO_ROOT_PASSWORD" ]; then
  fail "MinIO secret minio-auth not found in namespace minio"
  exit 1
fi

echo "=== Clean MinIO bucket (remove stale data from previous runs) ==="
MINIO_POD=$(kubectl get pod -n minio -l app=minio -o name 2>/dev/null | head -1)
if [ -n "$MINIO_POD" ]; then
  kubectl exec -n minio "$MINIO_POD" -- mc alias set myminio http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null 2>&1
  kubectl exec -n minio "$MINIO_POD" -- sh -c 'mc rb --force myminio/cnpg-backups 2>/dev/null; mc mb myminio/cnpg-backups' > /dev/null 2>&1
  ok "MinIO bucket cnpg-backups cleaned"
else
  fail "MinIO pod not found — skipping bucket cleanup"
fi

echo "=== Deploy test resources ==="
kubectl apply -f tests/db-backup/namespace.yaml
# Allow this test's namespace to reach MinIO :9000. Cilium unions this with the
# existing minio/platform-ingress policy; it is removed again in cleanup().
kubectl apply -f tests/db-backup/minio-access.yaml
kubectl create secret generic backup-creds -n "$NS" \
  --from-literal=ACCESS_KEY_ID="$MINIO_ROOT_USER" \
  --from-literal=ACCESS_SECRET_KEY="$MINIO_ROOT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f tests/db-backup/objectstore.yaml

echo "=== Deploy source cluster: $CLUSTER_SRC ==="
kubectl apply -f tests/db-backup/source-cluster.yaml

echo "  Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready cluster/$CLUSTER_SRC -n "$NS" --timeout=180s > /dev/null 2>&1 && {
  ok "Source cluster $CLUSTER_SRC is Ready"
} || {
  fail "Source cluster $CLUSTER_SRC not ready"
  kubectl get pods -n "$NS" 2>/dev/null | tail -5
  exit 1
}

echo "=== Write 100 rows ==="
PRIMARY=$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=$CLUSTER_SRC,cnpg.io/podRole=instance" -o name 2>/dev/null | head -1)
if [ -z "$PRIMARY" ]; then
  fail "No primary pod found"
  exit 1
fi

kubectl exec -n "$NS" "$PRIMARY" -- psql -U postgres -c "
  CREATE TABLE IF NOT EXISTS backup_test (id serial primary key, val text);
  TRUNCATE backup_test RESTART IDENTITY;
  INSERT INTO backup_test (val) SELECT 'row-' || generate_series FROM generate_series(1, 100);
" > /dev/null 2>&1 && {
  ok "Inserted 100 rows"
} || {
  fail "Failed to insert rows"
  exit 1
}

COUNT=$(kubectl exec -n "$NS" "$PRIMARY" -- psql -U postgres -t -c "SELECT count(*) FROM backup_test;" 2>/dev/null | tr -d ' ')
if [ "$COUNT" = "100" ]; then
  ok "Verified 100 rows in source cluster"
else
  fail "Expected 100 rows, got $COUNT"
  exit 1
fi

echo "=== Create backup ==="
kubectl apply -f tests/db-backup/backup.yaml

echo "  Waiting for backup to complete..."
for _ in $(seq 1 60); do
  PHASE=$(kubectl get backup -n "$NS" "$BACKUP_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$PHASE" = "completed" ]; then
    ok "Backup $BACKUP_NAME completed"
    break
  fi
  if [ "$PHASE" = "failed" ]; then
    fail "Backup $BACKUP_NAME failed"
    kubectl describe backup -n "$NS" "$BACKUP_NAME" 2>/dev/null | grep -E "Error|Message" | head -3
    exit 1
  fi
  sleep 5
done

if [ "$PHASE" != "completed" ]; then
  fail "Backup did not complete within 5 minutes"
  exit 1
fi

echo "=== Deploy recovery cluster: $CLUSTER_RECOVERY ==="
kubectl apply -f tests/db-backup/recovery-cluster.yaml

echo "  Waiting for recovery cluster to be ready (up to 300s)..."
kubectl wait --for=condition=Ready cluster/$CLUSTER_RECOVERY -n "$NS" --timeout=300s > /dev/null 2>&1 && {
  ok "Recovery cluster $CLUSTER_RECOVERY is Ready"
} || {
  fail "Recovery cluster $CLUSTER_RECOVERY not ready"
  kubectl get pods -n "$NS" 2>/dev/null | tail -5
  kubectl describe cluster -n "$NS" "$CLUSTER_RECOVERY" 2>/dev/null | grep -E "Message|Status" | head -5
  exit 1
}

echo "=== Verify 100 rows in recovery cluster ==="
RECOVERY_PRIMARY=$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=$CLUSTER_RECOVERY,cnpg.io/podRole=instance" -o name 2>/dev/null | head -1)
if [ -z "$RECOVERY_PRIMARY" ]; then
  fail "No recovery primary pod found"
  exit 1
fi

RECOVERY_COUNT=$(kubectl exec -n "$NS" "$RECOVERY_PRIMARY" -- psql -U postgres -t -c "SELECT count(*) FROM backup_test;" 2>/dev/null | tr -d ' ')
if [ "$RECOVERY_COUNT" = "100" ]; then
  ok "Verified 100 rows in recovery cluster (data restored correctly)"
else
  fail "Expected 100 rows in recovery, got $RECOVERY_COUNT"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
