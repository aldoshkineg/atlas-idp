#!/usr/bin/env bash
set -euo pipefail

echo "==> Waiting for vault-0 to be Ready..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=60s > /dev/null 2>&1 || {
	echo "ERROR: vault-0 not ready. Run 'make infra-apply' first."
	exit 1
}

echo "=== Fetching root token ==="
ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.vault-root}' | base64 -d)

kubectl exec -n vault vault-0 -c vault -- sh -c "
VAULT_ADDR=http://127.0.0.1:8200
vault login -address=\$VAULT_ADDR $ROOT_TOKEN > /dev/null
echo '=== Creating Kubernetes auth role for testing ==='
vault write -address=\$VAULT_ADDR auth/kubernetes/role/platform-read \
  bound_service_account_names=test-vault-inject \
  bound_service_account_namespaces=testing \
  policies=platform-read \
  ttl=1h
echo '=== Creating secret secret/platform/test ==='
vault kv put -address=\$VAULT_ADDR secret/platform/test value=hello-from-vault
echo '=== Verifying ==='
vault kv get -address=\$VAULT_ADDR secret/platform/test
"

echo ""
echo "Done. Secret 'secret/platform/test' created with value='hello-from-vault'"