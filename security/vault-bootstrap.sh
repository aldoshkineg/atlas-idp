#!/usr/bin/env bash
set -euo pipefail

echo "==> Waiting for vault-0 to be Ready..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=60s > /dev/null 2>&1 || {
	echo "ERROR: vault-0 not ready. Run 'make infra-apply' first."
	exit 1
}

# Vault Secret Bootstrap
# =======================
# Seeds test secrets into Vault for the testing namespace.
# Run once after vault-operator is healthy.
#
# Prerequisites:
#   - kubectl, jq
#   - kind cluster with Atlas IDP deployed
#   - vault-0 pod running (3/3 Ready)
#
# Usage:
#   ./security/vault-bootstrap.sh
#
# What it creates:
#   - KV v2 secret: secret/data/platform/test -> value=hello-from-vault
#
# This secret is consumed by:
#   - vault-test pod (via vault-agent template -> /vault/secrets/app-secrets)
#   - vault-agent-cm ConfigMap (template block in gitops/testing/)

echo "=== Fetching root token ==="
ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o json | jq -r '.data["vault-root"]' | base64 -d)

kubectl exec -n vault vault-0 -- sh -c "
VAULT_ADDR=http://127.0.0.1:8200
vault login -address=\$VAULT_ADDR $ROOT_TOKEN > /dev/null
echo '=== Creating secret secret/platform/test ==='
vault kv put -address=\$VAULT_ADDR secret/platform/test value=hello-from-vault
echo '=== Verifying ==='
vault kv get -address=\$VAULT_ADDR secret/platform/test
"

echo ""
echo "Done. Secret 'secret/platform/test' created with value='hello-from-vault'"
