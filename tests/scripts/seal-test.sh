#!/usr/bin/env bash
set -euo pipefail

NS="seal"
API_SVC="seal-api.seal.svc.cluster.local:8080"
WORKER_SVC="seal-worker.seal.svc.cluster.local:9090"
MINIO_HOST="minio.minio.svc.cluster.local:9000"
GATEWAY_PORT="30444"
CA_CERT="clusters/kind/certs/ca.crt"
PASS=0
FAIL=0
DOC_ID=""

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# --- helpers ---
in_pod() {
  kubectl exec seal-test -n "$NS" -- "$@"
}

await_doc_completed() {
  local id="$1" max=30
  for i in $(seq 1 "$max"); do
    status=$(in_pod curl -sf "http://$API_SVC/api/v1/documents/$id" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    [ "$status" = "completed" ] && return 0
    sleep 1
  done
  return 1
}

cleanup() {
  kubectl delete pod seal-test -n "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Seal Integration Test ==="
echo ""

# --- Step 1: K8s resources ---
echo "--- Step 1: Checking Kubernetes resources ---"

if kubectl get pod -l app.kubernetes.io/name=seal-api -n "$NS" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -q Running; then
  ok "seal-api pod is Running"
else
  fail "seal-api pod not Running"
fi

if kubectl get pod -l app.kubernetes.io/name=seal-worker -n "$NS" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -q Running; then
  ok "seal-worker pod is Running"
else
  fail "seal-worker pod not Running"
fi

if kubectl get pod -l app.kubernetes.io/name=seal-ui -n "$NS" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -q Running; then
  ok "seal-ui pod is Running"
else
  fail "seal-ui pod not Running"
fi

for svc in seal-api seal-worker seal-ui; do
  if kubectl get svc "$svc" -n "$NS" > /dev/null 2>&1; then
    ok "Service $svc exists"
  else
    fail "Service $svc not found"
  fi
done

for secret in seal-api-secret seal-worker-secret; do
  if kubectl get secret "$secret" -n "$NS" > /dev/null 2>&1; then
    ok "Secret $secret exists"
  else
    fail "Secret $secret not found"
  fi
done

echo ""

# --- Step 2: Deploy debug pod ---
echo "--- Step 2: Deploying debug pod ---"
kubectl apply -f tests/seal/test-pod.yaml > /dev/null
if kubectl wait --for=condition=Ready pod seal-test -n "$NS" --timeout=60s > /dev/null 2>&1; then
  ok "Debug pod ready"
else
  fail "Debug pod not ready"
fi
echo ""

# --- Step 3: API health ---
echo "--- Step 3: API health endpoints ---"
if in_pod curl -sf "http://$API_SVC/healthz" > /dev/null 2>&1; then
  ok "API /healthz responds"
else
  fail "API /healthz unreachable"
fi

if in_pod curl -sf "http://$API_SVC/readyz" > /dev/null 2>&1; then
  ok "API /readyz responds"
else
  fail "API /readyz unreachable"
fi
echo ""

# --- Step 4: Document CRUD ---
echo "--- Step 4: Document creation and processing ---"
RESP=$(in_pod curl -sf -X POST "http://$API_SVC/api/v1/documents" \
  -H "Content-Type: application/json" \
  -d '{"text":"Integration test PDF content"}') || true
DOC_ID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [ -n "$DOC_ID" ]; then
  ok "Document created (id=$DOC_ID)"
else
  fail "Document creation failed (response: $RESP)"
fi

if [ -n "$DOC_ID" ]; then
  if await_doc_completed "$DOC_ID"; then
    ok "Document $DOC_ID processed to completed"
  else
    fail "Document $DOC_ID not completed within 30s"
  fi

  DOC_DATA=$(in_pod curl -sf "http://$API_SVC/api/v1/documents/$DOC_ID" 2>/dev/null || echo "")
  S3_PATH=$(echo "$DOC_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('s3_path',''))" 2>/dev/null || echo "")
  if [ -n "$S3_PATH" ]; then
    ok "Document has s3_path: $S3_PATH"
  else
    fail "Document missing s3_path"
  fi

  VERIFY=$(in_pod curl -sf "http://$API_SVC/api/v1/documents/$DOC_ID/verify" 2>/dev/null || echo "")
  VALID=$(echo "$VERIFY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('valid',False))" 2>/dev/null || echo "false")
  if [ "$VALID" = "True" ]; then
    ok "Signature verification: valid"
  else
    fail "Signature verification failed (response: $VERIFY)"
  fi
fi
echo ""

# --- Step 5: Worker metrics ---
echo "--- Step 5: Worker metrics ---"
METRICS=$(in_pod curl -sf "http://$WORKER_SVC/metrics" 2>/dev/null || echo "")
if echo "$METRICS" | grep -q "pdf_sign_duration_seconds"; then
  ok "Worker metrics: pdf_sign_duration_seconds"
else
  fail "Worker metrics missing pdf_sign_duration_seconds"
fi
if echo "$METRICS" | grep -q "pdf_sign_errors_total"; then
  ok "Worker metrics: pdf_sign_errors_total"
else
  fail "Worker metrics missing pdf_sign_errors_total"
fi
echo ""

# --- Step 6: MinIO bucket (seal-outputs) ---
echo "--- Step 6: MinIO bucket seal-outputs ---"
BUCKET_LIST=$(in_pod curl -sf --aws-sigv4 "aws:amz:us-east-1:s3" --user "minioadmin:minioadminpassword" "http://$MINIO_HOST/seal-outputs/" 2>/dev/null || echo "")
if echo "$BUCKET_LIST" | grep -q "<Contents>"; then
  ok "MinIO bucket seal-outputs contains signed PDFs"
else
  fail "MinIO bucket seal-outputs empty or inaccessible"
fi
echo ""

# --- Step 7: Gateway external access ---
echo "--- Step 7: Gateway external access (https) ---"
if [ -f "$CA_CERT" ]; then
  GATEWAY_NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}' 2>/dev/null || echo "localhost")
  API_PATH="/api/v1/documents/$DOC_ID"
  if [ -n "$DOC_ID" ]; then
    if curl -sf --cacert "$CA_CERT" --resolve "seal.atlas:$GATEWAY_PORT:$GATEWAY_NODE" \
      "https://seal.atlas:$GATEWAY_PORT$API_PATH" > /dev/null 2>&1; then
      ok "Gateway: seal.atlas routes to API"
    else
      fail "Gateway: seal.atlas API unreachable"
    fi
  fi
  if curl -sf --cacert "$CA_CERT" --resolve "seal.atlas:$GATEWAY_PORT:$GATEWAY_NODE" \
    "https://seal.atlas:$GATEWAY_PORT/" -o /dev/null 2>&1; then
    ok "Gateway: seal.atlas/ serves UI"
  else
    fail "Gateway: seal.atlas/ unreachable"
  fi
else
  echo "  SKIP: CA cert $CA_CERT not found (run 'make seed-ca'?)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
