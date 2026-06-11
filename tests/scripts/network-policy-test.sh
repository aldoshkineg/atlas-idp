#!/usr/bin/env bash
set -euo pipefail

NS="netpol-test"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== NetworkPolicy Test ==="
echo ""

echo "  Waiting for pods to be ready..."
for pod in alpha beta gamma; do
  kubectl wait --for=condition=Ready "pod/$pod" -n "$NS" --timeout=120s > /dev/null 2>&1 || {
    fail "$pod pod not ready"
    exit 1
  }
done
ok "all pods ready"

echo ""
echo "--- Connectivity matrix ---"

# Matrix (self-tests skipped — Cilium hairpin may bypass policy):
#   alpha (no policy) → beta/gamma = alpha always allowed
#   beta  (allow-alpha) → alpha/gamma = allowed,  beta = skipped
#   gamma (allow-beta)  → alpha       = allowed,  beta/gamma = skipped

probe() {
  local src="$1" dst="$2" expect="$3" label="$4"
  local status=0
  kubectl exec "$src" -n "$NS" -- wget -qO- --timeout=3 "http://svc-${dst}:80/" > /dev/null 2>&1 || status=$?
  if [ "$status" = "0" ]; then
    if [ "$expect" = "allowed" ]; then
      ok "$label"
    else
      fail "$label (got connected, expected denied)"
    fi
  else
    if [ "$expect" = "denied" ]; then
      ok "$label"
    else
      fail "$label (got denied, expected allowed)"
    fi
  fi
}

probe alpha beta  allowed  "alpha → beta  (policy allow alpha — allowed)"
probe alpha gamma denied   "alpha → gamma (policy allow beta only — denied)"

probe beta  alpha allowed  "beta  → alpha (no policy on alpha — allowed)"
probe beta  gamma allowed  "beta  → gamma (policy allow beta — allowed)"

probe gamma alpha allowed  "gamma → alpha (no policy on alpha — allowed)"
probe gamma beta  denied   "gamma → beta  (policy allow alpha only — denied)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL