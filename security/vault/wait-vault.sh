#!/usr/bin/env bash
set -euo pipefail

# Wait until the local Kind Vault instance is ready for seeding.

kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=300s

kubectl -n vault exec vault-0 -c vault -- vault status -address=http://127.0.0.1:8200 >/dev/null

echo "Vault API is ready"
