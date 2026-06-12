#!/usr/bin/env bash
set -euo pipefail

NS="keda-test"
SCALER="keda-fast-scaler"
DEPLOY="keda-fast-test"
HPA="keda-hpa-$SCALER"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== KEDA Fast Cron Test ==="
echo ""

# --- Step 0: External Metrics API ---
echo "--- Step 0: Checking External Metrics API ---"
if kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" > /dev/null 2>&1; then
  ok "External Metrics API is available"
else
  fail "External Metrics API not available — KEDA metrics-server may be broken"
fi

# --- Step 1: Проверка что KEDA работает ---
echo ""
echo "--- Step 1: Checking KEDA deployment ---"
for deploy in keda-operator keda-operator-metrics-apiserver keda-admission-webhooks; do
  if kubectl wait --for=condition=Available "deployment/$deploy" -n keda --timeout=60s > /dev/null 2>&1; then
    ok "$deploy is ready"
  else
    fail "$deploy not ready — run 'make infra-apply' first"
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
  fi
done

# --- Step 2: Проверка CRD ---
echo ""
echo "--- Step 2: Checking KEDA CRDs ---"
for crd in scaledobjects.keda.sh scaledjobs.keda.sh triggerauthentications.keda.sh; do
  if kubectl get crd "$crd" > /dev/null 2>&1; then
    ok "CRD $crd exists"
  else
    fail "CRD $crd not found"
  fi
done

# --- Step 3: Применяем тестовые манифесты ---
echo ""
echo "--- Step 3: Applying test manifests ---"
kubectl apply -f tests/keda/namespace.yaml
kubectl apply -f tests/keda/deployment.yaml
kubectl apply -f tests/keda/scaled-object.yaml

echo "  Waiting for ScaledObject to be ready..."
if kubectl wait --for=condition=Ready scaledobject.keda.sh/$SCALER -n "$NS" --timeout=30s > /dev/null 2>&1; then
  ok "ScaledObject $SCALER is ready"
else
  fail "ScaledObject $SCALER not ready"
fi

# --- Step 4: Проверка что HPA создан ---
echo ""
echo "--- Step 4: Checking HPA was created ---"
if kubectl get hpa "$HPA" -n "$NS" > /dev/null 2>&1; then
  ok "HPA $HPA exists"
else
  fail "HPA $HPA not created by KEDA"
fi

# --- Step 5: Scale up (desiredReplicas → 3) ---
echo ""
echo "--- Step 5: Scaling up (0 → 3) ---"
START=$SECONDS
kubectl patch scaledobject $SCALER -n "$NS" --type='json' \
  -p='[{"op": "replace", "path": "/spec/triggers/0/metadata/desiredReplicas", "value": "3"}]'
echo "  desiredReplicas=3, waiting for pods (timeout 60s)..."

for i in $(seq 1 60); do
  REPLICAS=$(kubectl get deployment $DEPLOY -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${REPLICAS:-0}" -ge 3 ]; then
    DURATION=$((SECONDS - START))
    ok "Deployment scaled up to 3 in ${DURATION}s"
    break
  fi
  sleep 1
done
if [ "${REPLICAS:-0}" -lt 3 ]; then
  fail "Deployment did not scale up to 3 within 60s"
fi

# --- Step 6: Scale down (desiredReplicas → 0) ---
# HPA имеет built-in downscale stabilization (~5 min), поэтому реальное удаление подов
# может быть отложено. Основная проверка — что KEDA изменил metric на HPA.
# Дополнительно пробуем дождаться фактического scale-down, но без блокировки.
echo ""
echo "--- Step 6: Scaling down (3 → 0) ---"
START=$SECONDS
kubectl patch scaledobject $SCALER -n "$NS" --type='json' \
  -p='[{"op": "replace", "path": "/spec/triggers/0/metadata/desiredReplicas", "value": "0"}]'
echo "  desiredReplicas=0, checking HPA metric..."

METRIC_OK=0
for i in $(seq 1 30); do
  AVG=$(kubectl get hpa "$HPA" -n "$NS" -o jsonpath='{.status.currentMetrics[0].external.current.averageValue}' 2>/dev/null || echo "")
  if [ "${AVG}" = "0" ]; then
    DURATION=$((SECONDS - START))
    ok "HPA metric changed to 0 in ${DURATION}s"
    METRIC_OK=1
    break
  fi
  sleep 1
done
if [ "$METRIC_OK" -eq 0 ]; then
  AVG_CHECK=$(kubectl get hpa "$HPA" -n "$NS" -o jsonpath='{.status.currentMetrics[0].external.current.averageValue}' 2>/dev/null || echo "N/A")
  fail "HPA metric did not change to 0 within 30s (got: ${AVG_CHECK})"
fi

echo "  Checking actual replica count (non-blocking, 10s)..."
for i in $(seq 1 10); do
  REPLICAS=$(kubectl get deployment $DEPLOY -n "$NS" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
  if [ "${REPLICAS}" = "0" ]; then
    DURATION=$((SECONDS - START))
    echo "  INFO: Deployment actually scaled down to 0 in ${DURATION}s"
    break
  fi
  sleep 1
done

# --- Итог ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
