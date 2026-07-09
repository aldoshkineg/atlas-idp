#!/usr/bin/env bash
set -uo pipefail

# Cosign + Kyverno admission control check.
#
# Verifies:
#   1. Kyverno is running and ClusterPolicies are Ready
#   2. Our signed image actually carries a Cosign signature (offline cosign verify)
#   3. A valid (signed) image is admitted by Kyverno and reported as PASS
#      ("image verified"). Requires the policy to run with mutateDigest=true
#      (Enforce mode) — Audit mode cannot resolve tag digests, so it cannot verify.
#   4. An invalid (unsigned) image is REJECTED by the webhook (Enforce).
#
# Requires KUBECONFIG to point at the target cluster (Talos: /var/tmp/atlas/talos/kubeconfig).
# Image tags are overridable via env vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NS="cosign-kyverno-test"
POLICY="require-image-signature"
VALID_IMAGE="${VALID_IMAGE:-ghcr.io/aldoshkineg/seal-api:v0.52.0}"
INVALID_IMAGE="${INVALID_IMAGE:-ghcr.io/aldoshkineg/seal-api:v0.25.0}"
PUBKEY="${PUBKEY:-$REPO_ROOT/security/cosign/cosign.pub}"
VALID_POD="valid-signed"
INVALID_POD="invalid-unsigned"
COSIGN_BIN="${COSIGN_BIN:-cosign}"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
info() { echo "  INFO: $1"; }

cleanup() {
  kubectl delete namespace "$NS" --ignore-not-found > /dev/null 2>&1 || true
}
trap cleanup EXIT

# wait_for_report POD RESULT  — wait (<=60s) for a require-image-signature
# result of the given kind for the pod identified by its scope name.
wait_for_report() {
  local pod="$1" want="$2"
  for _ in $(seq 1 20); do
    if kubectl get policyreport -n "$NS" -o json 2>/dev/null | \
       jq -e --arg pod "$pod" --arg want "$want" '
         .items[]? | select(.scope.name==$pod)
         | .results[]?
         | select(.policy=="'"$POLICY"'" and .result==$want)' > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

echo "=== Cosign + Kyverno Admission Control Check ==="
echo "  cluster : ${KUBECONFIG:-<default>}"
echo "  valid   : $VALID_IMAGE"
echo "  invalid : $INVALID_IMAGE"
echo ""

# --- Step 0: Kyverno is running ---
echo "--- Step 0: Kyverno deployment ---"
if ! kubectl get ns kyverno > /dev/null 2>&1; then
  fail "namespace 'kyverno' not found — Kyverno is not installed"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi
READY_DEPLOYS=0
TOTAL_DEPLOYS=0
for deploy in $(kubectl get deployments -n kyverno -o jsonpath='{.items[*].metadata.name}'); do
  TOTAL_DEPLOYS=$((TOTAL_DEPLOYS+1))
  if kubectl wait --for=condition=Available "deployment/$deploy" -n kyverno --timeout=60s > /dev/null 2>&1; then
    READY_DEPLOYS=$((READY_DEPLOYS+1))
  else
    fail "deployment kyverno/$deploy not ready"
  fi
done
if [ "$READY_DEPLOYS" -eq "$TOTAL_DEPLOYS" ] && [ "$TOTAL_DEPLOYS" -gt 0 ]; then
  ok "Kyverno ready ($READY_DEPLOYS/$TOTAL_DEPLOYS deployments)"
else
  fail "Kyverno not fully ready ($READY_DEPLOYS/$TOTAL_DEPLOYS)"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# --- Step 1: ClusterPolicies are Ready ---
echo ""
echo "--- Step 1: ClusterPolicies ---"
for p in require-image-signature disallow-latest-tag require-run-as-non-root disallow-privileged require-labels; do
  if ! kubectl get clusterpolicy "$p" > /dev/null 2>&1; then
    fail "ClusterPolicy '$p' not found"
    continue
  fi
  status=$(kubectl get clusterpolicy "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$status" = "True" ]; then
    ok "ClusterPolicy '$p' is Ready"
  else
    fail "ClusterPolicy '$p' not Ready (status=$status)"
  fi
done

# Detect enforcement mode of the signature policy.
ACTION=$(kubectl get clusterpolicy "$POLICY" -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null)
MD=$(kubectl get clusterpolicy "$POLICY" -o jsonpath='{.spec.rules[0].verifyImages[0].mutateDigest}' 2>/dev/null)
info "require-image-signature: validationFailureAction='${ACTION:-unknown}', mutateDigest='${MD:-unknown}'"
if [ "$ACTION" != "Enforce" ] || [ "$MD" != "true" ]; then
  info "NOTE: image verification requires Enforce + mutateDigest=true; Audit mode cannot resolve tag digests."
fi

# --- Step 2: Cosign signature present on the valid image (offline) ---
echo ""
echo "--- Step 2: cosign verify (offline, against repo pubkey) ---"
if [ ! -f "$PUBKEY" ]; then
  fail "public key not found at $PUBKEY"
elif ! command -v "$COSIGN_BIN" > /dev/null 2>&1; then
  fail "cosign binary '$COSIGN_BIN' not found in PATH"
else
  if timeout 90 "$COSIGN_BIN" verify --key "$PUBKEY" --insecure-ignore-tlog "$VALID_IMAGE" > /dev/null 2>&1; then
    ok "$VALID_IMAGE carries a valid Cosign signature"
  else
    fail "$VALID_IMAGE: cosign verify failed (no/!matching signature or registry unreachable)"
  fi
fi

# --- Test namespace (not in the policy exclude list) ---
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

# --- Step 3: Valid (signed) image is admitted and verified by Kyverno ---
echo ""
echo "--- Step 3: valid signed image admission + verification ---"
kubectl delete pod "$VALID_POD" -n "$NS" --ignore-not-found > /dev/null 2>&1
if ! kubectl run "$VALID_POD" -n "$NS" --image="$VALID_IMAGE" --command -- sleep 3600 > /dev/null 2>&1; then
  fail "signed image pod '$VALID_POD' was rejected (expected admitted)"
else
  ok "signed image pod '$VALID_POD' admitted"
fi
echo "  Waiting for Kyverno PolicyReport PASS (timeout 60s)..."
if wait_for_report "$VALID_POD" pass; then
  ok "Kyverno reported PASS (image verified) for '$VALID_POD'"
else
  fail "Kyverno did not report PASS for signed image '$VALID_POD'"
fi

# --- Step 4: Invalid (unsigned) image must be rejected by Kyverno ---
# Kyverno resolves the image digest via the node image cache; an image that is
# not yet pulled to a node yields "missing digest" and (failurePolicy=Ignore)
# is admitted. Warm-pull the unsigned image in an EXCLUDED namespace first so
# its digest is resolvable, then the policy can actually verify (and reject) it.
echo ""
echo "--- Step 4: invalid unsigned image handling (mode=$ACTION) ---"
echo "  warming unsigned image in excluded ns 'default' (so digest resolves)..."
kubectl run warm-inv -n default --image="$INVALID_IMAGE" --command -- sleep 3600 > /dev/null 2>&1 || true
kubectl wait --for=condition=Ready "pod/warm-inv" -n default --timeout=60s > /dev/null 2>&1 || true
kubectl delete pod warm-inv -n default --ignore-not-found > /dev/null 2>&1 || true

kubectl delete pod "$INVALID_POD" -n "$NS" --ignore-not-found > /dev/null 2>&1
if kubectl run "$INVALID_POD" -n "$NS" --image="$INVALID_IMAGE" --command -- sleep 3600 2>/tmp/kyverno-reject.err; then
  fail "unsigned image '$INVALID_POD' was admitted (expected rejected)"
else
  REASON=$(cat /tmp/kyverno-reject.err 2>/dev/null || true)
  if echo "$REASON" | grep -qi "kyverno\|verify\|signature\|policy\|admission\|unverified\|no signatures"; then
    ok "unsigned image rejected by Kyverno webhook: $(echo "$REASON" | grep -i "verify\|signature\|unverified\|no signatures" | head -1)"
  else
    fail "unsigned image rejected but not by Kyverno: $REASON"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
