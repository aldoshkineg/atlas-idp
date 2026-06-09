#!/usr/bin/env bash
set -euo pipefail

# Vault Secret Bootstrap
# =======================
# Seeds test secrets into Vault for the testing namespace.
# Run once after vault-operator is healthy.
#
# Prerequisites:
#   - kubectl, vault CLI, jq
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

VAULT_ADDR=${VAULT_ADDR:-https://vault.atlas:443}
VAULT_SKIP_VERIFY=true
export VAULT_ADDR VAULT_SKIP_VERIFY

echo "=== Fetching root token ==="
ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o json | jq -r '.data["vault-root"]' | base64 -d)
vault login "$ROOT_TOKEN" > /dev/null

echo "=== Creating secret 'secret/platform/test' ==="
vault kv put secret/platform/test value=hello-from-vault

echo "=== Verifying ==="
vault kv get secret/platform/test

echo ""
echo "Done. Secret 'secret/platform/test' created with value='hello-from-vault'"
