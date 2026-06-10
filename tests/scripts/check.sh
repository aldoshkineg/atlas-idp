#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Test: TLS Gateway ==="

echo "  Waiting for test-app pod..."
kubectl wait --for=condition=Ready pod -l app=test-app -n testing --timeout=60s > /dev/null 2>&1 || {
  fail "test-app pod not ready"
  exit 1
}

echo "  Waiting for test-ca-cert to be ready..."
kubectl wait --for=condition=Ready certificate/test-ca-cert -n nginx-gateway-fabric --timeout=60s > /dev/null 2>&1 || {
  fail "test-ca-cert not ready"
}

if curl -sf --cacert clusters/kind/certs/ca.crt https://test-ca.atlas/ > /dev/null 2>&1; then
  ok "TLS gateway responds at https://test-ca.atlas/"
else
  fail "TLS gateway unreachable"
fi

echo "=== Test: Vault Injection ==="

echo "  Waiting for vault-inject-test pod..."
kubectl wait --for=condition=Ready pod/vault-inject-test -n testing --timeout=120s > /dev/null 2>&1 || {
  fail "vault-inject-test pod not ready"
  exit 1
}

echo "  Checking for injected secrets..."
FOUND=0
for i in $(seq 1 10); do
  if kubectl logs -n testing vault-inject-test 2>&1 | grep -q "hello-from-vault"; then
    ok "Vault secrets injected into pod"
    FOUND=1
    break
  fi
  sleep 2
done
[ "$FOUND" -eq 0 ] && fail "Vault secrets not found in pod logs"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL