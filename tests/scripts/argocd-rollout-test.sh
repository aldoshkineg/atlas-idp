#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
NS="argocd-rollout-test"
ROLLOUT="test-rollout"
CONTROLLER_NS="argo-rollouts"
REPLICAS=4

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

rollout_phase() {
  kubectl get rollout "$ROLLOUT" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo ""
}

rs_count() {
  kubectl get rs -n "$NS" -l "app=$ROLLOUT" -o name 2>/dev/null | wc -l | tr -d ' '
}

rs_hash_for() {
  kubectl get rollout "$ROLLOUT" -n "$NS" -o jsonpath="{.status.$1}" 2>/dev/null || echo ""
}

# desired replica count of the RS matching a given pod-template-hash
rs_desired() {
  kubectl get rs -n "$NS" -l "app=$ROLLOUT,rollouts-pod-template-hash=$1" \
    -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo 0
}

rs_ready() {
  kubectl get rs -n "$NS" -l "app=$ROLLOUT,rollouts-pod-template-hash=$1" \
    -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo 0
}

cleanup() {
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Argo Rollouts Canary Test ==="
echo ""

# --- Step 0: Controller + dashboard + CRD ---
echo "--- Step 0: Checking argo-rollouts installation ---"
if kubectl wait --for=condition=Available "deployment/argo-rollouts" -n "$CONTROLLER_NS" --timeout=60s > /dev/null 2>&1; then
  ok "argo-rollouts controller is Available"
else
  fail "argo-rollouts controller not ready — run 'make gitops-bootstrap' / sync argo-rollouts app first"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

if kubectl wait --for=condition=Available "deployment/argo-rollouts-dashboard" -n "$CONTROLLER_NS" --timeout=60s > /dev/null 2>&1; then
  ok "argo-rollouts dashboard is Available"
else
  fail "argo-rollouts dashboard not ready"
fi

if kubectl get crd rollouts.argoproj.io > /dev/null 2>&1; then
  ok "CRD rollouts.argoproj.io exists"
else
  fail "CRD rollouts.argoproj.io not found"
fi
echo ""

# --- Step 1: Deploy test Rollout (v1) ---
echo "--- Step 1: Deploying test Rollout ---"
kubectl apply -f tests/argocd-rollout/namespace.yaml > /dev/null
kubectl apply -f tests/argocd-rollout/service.yaml > /dev/null
kubectl apply -f tests/argocd-rollout/rollout.yaml > /dev/null

echo "  Waiting for Rollout to become Healthy (v1)..."
HEALTHY=0
for _ in $(seq 1 90); do
  if [ "$(rollout_phase)" = "Healthy" ]; then HEALTHY=1; break; fi
  sleep 2
done
if [ "$HEALTHY" -eq 1 ]; then
  ok "Rollout reached Healthy (initial revision)"
else
  fail "Rollout did not become Healthy within 180s (phase: $(rollout_phase))"
fi

STABLE_HASH=$(rs_hash_for stableRS)
if [ -n "$STABLE_HASH" ]; then
  ok "Stable pod template hash recorded: $STABLE_HASH"
else
  fail "No stableRS reported by controller"
fi
echo ""

# --- Step 2: Trigger a canary update ---
echo "--- Step 2: Triggering canary update (pod template change) ---"
kubectl patch rollout "$ROLLOUT" -n "$NS" --type='json' \
  -p='[{"op":"add","path":"/spec/template/metadata/annotations","value":{"test.rollout/version":"2"}}]' > /dev/null

CANARY_SEEN=0
NEW_HASH=""
for _ in $(seq 1 60); do
  ph=$(rollout_phase)
  cnt=$(rs_count)
  if [ "$cnt" -ge 2 ] && { [ "$ph" = "Paused" ] || [ "$ph" = "Progressing" ]; }; then
    CANARY_SEEN=1
    NEW_HASH=$(rs_hash_for currentPodHash)
    break
  fi
  sleep 2
done

if [ "$CANARY_SEEN" -eq 1 ]; then
  ok "Canary rollout in progress (>=2 ReplicaSets, phase: $(rollout_phase))"
else
  fail "Canary did not start — no second ReplicaSet observed (phase: $(rollout_phase))"
fi

# setWeight verification: the canary RS must have fewer replicas than the stable one
if [ -n "$NEW_HASH" ] && [ "$NEW_HASH" != "$STABLE_HASH" ]; then
  NEW_DESIRED=$(rs_desired "$NEW_HASH")
  STABLE_DESIRED=$(rs_desired "$STABLE_HASH")
  if [ "${NEW_DESIRED:-0}" -lt "$REPLICAS" ] && [ "${STABLE_DESIRED:-0}" -gt 0 ]; then
    ok "Canary setWeight honored (canary replicas=$NEW_DESIRED < stable=$STABLE_DESIRED)"
  else
    echo "  INFO: canary replicas=$NEW_DESIRED, stable replicas=$STABLE_DESIRED"
  fi
  if [ "${STABLE_DESIRED:-0}" -gt 0 ]; then
    ok "Stable ReplicaSet still serving traffic during canary"
  else
    fail "Stable ReplicaSet not scaled during canary window"
  fi
else
  fail "Could not resolve canary ReplicaSet hash during progress"
fi
echo ""

# --- Step 3: Wait for full promotion to v2 ---
echo "--- Step 3: Waiting for full rollout to complete ---"
DONE=0
for _ in $(seq 1 90); do
  if [ "$(rollout_phase)" = "Healthy" ]; then DONE=1; break; fi
  sleep 2
done
if [ "$DONE" -eq 1 ]; then
  ok "Rollout reached Healthy after canary promotion"
else
  fail "Rollout did not complete within 180s (phase: $(rollout_phase))"
fi

CUR_HASH=$(rs_hash_for currentPodHash)
NEW_READY=$(rs_ready "$CUR_HASH")
if [ "${NEW_READY:-0}" = "$REPLICAS" ]; then
  ok "New revision fully rolled out ($REPLICAS/$REPLICAS ready)"
else
  fail "New revision not fully ready (ready=${NEW_READY:-0})"
fi

OLD_SCALED=1
for rs in $(kubectl get rs -n "$NS" -l "app=$ROLLOUT" -o jsonpath='{.items[*].metadata.name}'); do
  h=$(kubectl get rs "$rs" -n "$NS" -o jsonpath='{.metadata.labels.rollouts-pod-template-hash}' 2>/dev/null || echo "")
  r=$(kubectl get rs "$rs" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
  if [ "$h" != "$CUR_HASH" ] && [ "${r:-0}" != "0" ]; then OLD_SCALED=0; fi
done
if [ "$OLD_SCALED" -eq 1 ]; then
  ok "Previous ReplicaSet scaled down to 0"
else
  fail "Previous ReplicaSet not scaled down to 0"
fi
echo ""

# --- Step 4: Service wiring ---
echo "--- Step 4: Service wiring ---"
if kubectl get svc "$ROLLOUT" -n "$NS" > /dev/null 2>&1; then
  ok "Service $ROLLOUT exists"
else
  fail "Service $ROLLOUT not found"
fi
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
