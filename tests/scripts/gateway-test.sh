#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f tests/gateway/namespace.yaml
kubectl apply -f tests/gateway/app.yaml
kubectl apply -f tests/gateway/certificate.yaml

echo "  Waiting for test-app pod..."
kubectl wait --for=condition=Ready pod -l app=test-app -n testing --timeout=60s > /dev/null 2>&1

echo "  Waiting for test-ca-cert to be ready..."
kubectl wait --for=condition=Ready certificate/test-ca-cert -n kube-system --timeout=60s > /dev/null 2>&1

echo "  Waiting for gateway listener/route to be programmed..."
kubectl wait --for=condition=Accepted httproute/test-app-route -n testing --timeout=60s > /dev/null 2>&1 || true

echo "  Probing https://test-ca.atlas/ ..."
ok=0
for _ in $(seq 1 30); do
  if curl -sf --cacert security/certs/ca.crt https://test-ca.atlas/ > /dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done

if [ "$ok" -eq 1 ]; then
  echo "  PASS: TLS gateway responds at https://test-ca.atlas/"
else
  echo "  FAIL: TLS gateway unreachable"
  exit 1
fi
