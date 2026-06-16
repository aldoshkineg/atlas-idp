#!/usr/bin/env bash
set -euo pipefail

echo "==> Waiting for vault-0 to be Ready..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=60s > /dev/null 2>&1 || {
	echo "ERROR: vault-0 not ready. Run 'make infra-apply' first."
	exit 1
}

ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.vault-root}' | base64 -d)
kubectl exec -n vault vault-0 -c vault -- vault login -address=http://127.0.0.1:8200 "$ROOT_TOKEN" > /dev/null

kubectl exec -n vault vault-0 -c vault -- sh -c "
VAULT_ADDR=http://127.0.0.1:8200
vault write -address=\$VAULT_ADDR auth/kubernetes/role/platform-read \
  bound_service_account_names=test-vault-inject \
  bound_service_account_namespaces=testing \
  policies=platform-read \
  ttl=1h || true
vault kv put -address=\$VAULT_ADDR secret/platform/test value=hello-from-vault
vault kv get -address=\$VAULT_ADDR secret/platform/test
"

echo ""
echo "Done. Secret 'secret/platform/test' created with value='hello-from-vault'"

kubectl apply -f tests/vault

echo "  Waiting for vault-inject-test pod..."
kubectl wait --for=condition=Ready pod/vault-inject-test -n testing --timeout=120s > /dev/null 2>&1

echo "  Checking for injected secrets..."
FOUND=0
for _ in $(seq 1 10); do
  if kubectl logs -n testing vault-inject-test 2>&1 | grep -q "hello-from-vault"; then
    echo "  PASS: Vault secrets injected into pod"
    FOUND=1
    break
  fi
  sleep 2
done
if [ "$FOUND" -eq 0 ]; then
  echo "  FAIL: Vault secrets not found in pod logs"
  exit 1
fi
