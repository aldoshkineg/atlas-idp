#!/usr/bin/env bash
set -euo pipefail

NS="redis"
APP="redis"
SECRET="redis-auth"
SERVICE="redis-master"
POD_SELECTOR="app.kubernetes.io/instance=$APP,app.kubernetes.io/component=master"
TS=$(date +%s)
KEY="atlas-redis-test-$TS"
QUEUE="atlas-redis-queue-$TS"
VALUE="redis-test-value-$TS"
REDIS_PASSWORD=""
POD=""
STREAM_ID=""

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

cleanup() {
  if [ -n "$REDIS_PASSWORD" ] && [ -n "$POD" ]; then
    kubectl exec -n "$NS" "$POD" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DEL "$KEY" >/dev/null 2>&1 || true
    if [ -n "$STREAM_ID" ]; then
      kubectl exec -n "$NS" "$POD" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning XDEL "$QUEUE" "$STREAM_ID" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

redis_exec() {
  kubectl exec -n "$NS" "$POD" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning "$@"
}

echo "=== Redis Test ==="
echo ""

echo "--- Step 1: Checking ArgoCD Application ---"
SYNC_STATUS=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
HEALTH_STATUS=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

if [ "$SYNC_STATUS" = "Synced" ]; then
  ok "ArgoCD Application $APP is Synced"
else
  fail "ArgoCD Application $APP sync status is '$SYNC_STATUS'"
fi

if [ "$HEALTH_STATUS" = "Healthy" ]; then
  ok "ArgoCD Application $APP is Healthy"
else
  fail "ArgoCD Application $APP health status is '$HEALTH_STATUS'"
fi

echo ""
echo "--- Step 2: Checking ExternalSecret and Secret ---"
ES_READY=$(kubectl get externalsecret "$SECRET" -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$ES_READY" = "True" ]; then
  ok "ExternalSecret $SECRET is Ready"
else
  fail "ExternalSecret $SECRET is not Ready (got: $ES_READY)"
fi

REDIS_PASSWORD=$(kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.data.redis-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [ -n "$REDIS_PASSWORD" ]; then
  ok "Secret $SECRET contains redis-password"
else
  fail "Secret $SECRET does not contain redis-password"
fi

echo ""
echo "--- Step 3: Checking Redis service and endpoints ---"
SERVICE_PORT=$(kubectl get service "$SERVICE" -n "$NS" -o jsonpath='{.spec.ports[?(@.port==6379)].port}' 2>/dev/null || echo "")
if [ "$SERVICE_PORT" = "6379" ]; then
  ok "Service $SERVICE exposes port 6379"
else
  fail "Service $SERVICE does not expose port 6379 (got: $SERVICE_PORT)"
fi

ENDPOINTS=$(kubectl get endpoints "$SERVICE" -n "$NS" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$ENDPOINTS" ]; then
  ok "Service $SERVICE has ready endpoints: $ENDPOINTS"
else
  fail "Service $SERVICE has no ready endpoints"
fi

POD=$(kubectl get pod -n "$NS" -l "$POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$POD" ]; then
  fail "Redis pod not found by selector $POD_SELECTOR"
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi
ok "Redis pod found for functional checks: $POD"

echo ""
echo "--- Step 4: Checking Redis authentication ---"
NOAUTH_OUTPUT=$(kubectl exec -n "$NS" "$POD" -c redis -- redis-cli PING 2>&1 || true)
if [[ "$NOAUTH_OUTPUT" == *"NOAUTH"* ]]; then
  ok "Redis rejects requests without password"
else
  fail "Redis accepted unauthenticated request"
fi

PING_OUTPUT=$(redis_exec PING 2>/dev/null || true)
if [ "$PING_OUTPUT" = "PONG" ]; then
  ok "Redis responds to authenticated PING"
else
  fail "Authenticated Redis PING failed (got: $PING_OUTPUT)"
fi

echo ""
echo "--- Step 5: Checking Redis key-value path ---"
SET_OUTPUT=$(redis_exec SET "$KEY" "$VALUE" EX 300 2>/dev/null || true)
if [ "$SET_OUTPUT" = "OK" ]; then
  ok "Redis SET succeeded"
else
  fail "Redis SET failed (got: $SET_OUTPUT)"
fi

GET_OUTPUT=$(redis_exec GET "$KEY" 2>/dev/null || true)
if [ "$GET_OUTPUT" = "$VALUE" ]; then
  ok "Redis GET returned expected value"
else
  fail "Redis GET returned unexpected value: $GET_OUTPUT"
fi

echo ""
echo "--- Step 6: Checking Redis Streams queue path ---"
STREAM_ID=$(redis_exec XADD "$QUEUE" '*' message "$VALUE" 2>/dev/null || true)
if [[ "$STREAM_ID" == *-* ]]; then
  ok "Redis XADD succeeded: $STREAM_ID"
else
  fail "Redis XADD failed (got: $STREAM_ID)"
fi

READ_OUTPUT=$(redis_exec XREAD COUNT 1 STREAMS "$QUEUE" 0 2>/dev/null || true)
if [[ "$READ_OUTPUT" == *"$VALUE"* ]]; then
  ok "Redis XREAD returned queued message"
else
  fail "Redis XREAD did not return queued message"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit "$FAIL"
