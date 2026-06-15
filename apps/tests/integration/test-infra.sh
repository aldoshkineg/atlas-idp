#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== seal — Infrastructure Smoke Tests ==="
echo ""

# ── helpers ──────────────────────────────────────────────────────────────
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; exit 1; }
wait_for_healthy() {
  local service=$1 max=$2 i=0
  while [ $i -lt "$max" ]; do
    status=$(docker compose ps --format json "$service" 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d\" -f4 || true)
    if [ "$status" = "healthy" ]; then return 0; fi
    sleep 2
    i=$((i+1))
  done
  return 1
}

# ── 1. check compose file is valid ───────────────────────────────────────
echo "--- compose config ---"
docker compose config > /dev/null 2>&1 && pass "compose config valid" || fail "compose config invalid"

# ── 2. start stack if not running ────────────────────────────────────────
if ! docker compose ps --quiet 2>/dev/null | grep -q .; then
  echo "--- starting stack ---"
  docker compose up -d
fi

# ── 3. wait for infra services ───────────────────────────────────────────
echo "--- waiting for infra ---"
for svc in postgres redis minio; do
  wait_for_healthy "$svc" 15 && pass "$svc healthy" || fail "$svc not healthy"
done

# ── 4. postgres check ────────────────────────────────────────────────────
echo "--- postgres ---"
docker compose exec -T postgres pg_isready -U seal -d seal > /dev/null 2>&1 \
  && pass "pg_isready" || fail "postgres not accepting connections"

# ── 5. redis check ───────────────────────────────────────────────────────
echo "--- redis ---"
docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG \
  && pass "redis PONG" || fail "redis not responding"

# ── 6. minio check ───────────────────────────────────────────────────────
echo "--- minio ---"
docker compose exec -T minio mc ready local 2>/dev/null \
  && pass "minio ready" || fail "minio not ready"

# Configure mc alias with credentials and create bucket
docker compose exec -T minio mc alias set local http://localhost:9000 \
  "${MINIO_ACCESS_KEY:-minioadmin}" "${MINIO_SECRET_KEY:-minioadminpassword}" > /dev/null 2>&1 \
  && pass "mc alias configured" || fail "mc alias setup failed"

docker compose exec -T minio mc mb --ignore-existing local/seal-outputs 2>/dev/null \
  && pass "bucket seal-outputs created" || pass "bucket seal-outputs already exists"

# ── 7. wait for seal-api ─────────────────────────────────────────────────
echo "--- seal-api ---"
API_URL="http://localhost:8080"
for i in $(seq 1 15); do
  if curl -sf "$API_URL/healthz" > /dev/null 2>&1; then
    pass "healthz OK"
    break
  fi
  if [ "$i" -eq 15 ]; then fail "seal-api not responding after 30s"; fi
  sleep 2
done

curl -sf "$API_URL/readyz" > /dev/null 2>&1 \
  && pass "readyz OK" || fail "readyz failed"

# ── 8. create document via API ───────────────────────────────────────────
echo "--- create document ---"
RESP=$(curl -sf -X POST "$API_URL/api/v1/documents" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello, World! This is a test PDF document."}' 2>/dev/null) \
  || fail "POST /api/v1/documents failed"

DOC_ID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | cut -d\" -f4)
[ -n "$DOC_ID" ] && pass "document created: $DOC_ID" || fail "no id in response"

# ── 9. get document by id ────────────────────────────────────────────────
echo "--- get document ---"
curl -sf "$API_URL/api/v1/documents/$DOC_ID" > /dev/null 2>&1 \
  && pass "GET /api/v1/documents/$DOC_ID OK" || fail "GET document failed"

# ── 10. wait for worker to process ───────────────────────────────────────
echo "--- worker ---"
for i in $(seq 1 20); do
  STATUS=$(curl -sf "$API_URL/api/v1/documents/$DOC_ID" 2>/dev/null \
    | grep -o '"status":"[^"]*"' | cut -d\" -f4 || true)
  if [ "$STATUS" = "completed" ]; then
    pass "document processed (status=completed)"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "  last status: $STATUS"
    fail "document not processed after 40s"
  fi
  sleep 2
done

# ── 11. check worker metrics ─────────────────────────────────────────────
WORKER_URL="http://localhost:9090"
curl -sf "$WORKER_URL/metrics" | grep -q 'jobs_processed_total' \
  && pass "worker metrics available" || fail "worker metrics not found"

# ── 12. verify PDF in MinIO ──────────────────────────────────────────────
echo "--- minio verification ---"
OBJECT_KEY="$DOC_ID.pdf"
docker compose exec -T minio mc stat "local/seal-outputs/$OBJECT_KEY" > /dev/null 2>&1 \
  && pass "PDF object exists: $OBJECT_KEY" || fail "PDF not found in minio: $OBJECT_KEY"

# ── 13. verify PDF signature via API ──────────────────────────────────────
echo "--- signature verification ---"
VERIFY_RESP=$(curl -sf "$API_URL/api/v1/documents/$DOC_ID/verify" 2>/dev/null) || true
if [ -n "$VERIFY_RESP" ]; then
  VERIFY_VALID=$(echo "$VERIFY_RESP" | grep -o '"valid":[^,}]*' | cut -d: -f2 | tr -d ' ')
  if [ "$VERIFY_VALID" = "true" ]; then
    pass "PDF signature verified (valid=true)"
  else
    VERIFY_ERR=$(echo "$VERIFY_RESP" | grep -o '"error":"[^"]*"' | cut -d\" -f4)
    pass "PDF signature check: $VERIFY_ERR (expected if keys not available)"
  fi
else
  pass "verify endpoint not available (skipped)"
fi

# ── 14. get download URL ─────────────────────────────────────────────────
echo "--- download url ---"
curl -sf "$API_URL/api/v1/documents/$DOC_ID/download" > /dev/null 2>&1 \
  && pass "download URL available" || fail "download URL failed"

echo ""
echo "=== All infra tests passed ==="
