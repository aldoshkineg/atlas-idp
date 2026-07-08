#!/usr/bin/env bash

set -eo pipefail

export KUBECONFIG="${KUBECONFIG:-/var/tmp/atlas/talos/kubeconfig}"
ARGOCD="argocd"
ARGOCD_SERVER="argocd-cli.atlas"
ARGOCD_USER="admin"
SECRET_NAME="argocd-initial-admin-secret"
NAMESPACE="argocd"

echo "==> Fetching admin password..."
if ! ARGOCD_PASSWORD=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode); then
    echo "⚠️  Failed to fetch password. Enter manually:"
    read -rs ARGOCD_PASSWORD
fi

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "❌ Error: Password cannot be empty."
    exit 1
fi

echo "==> Logging into ArgoCD CLI..."
# Remove stale config to ensure clean state
rm -f "$HOME/.config/argocd/config"

echo "y" | $ARGOCD login "$ARGOCD_SERVER" --username "$ARGOCD_USER" --password "$ARGOCD_PASSWORD"
ARGO_EXIT=$?

if [ $ARGO_EXIT -ne 0 ]; then
    echo "❌ Error: ArgoCD login failed."
    exit 1
fi

echo "✅ Login successful."
echo "    Run: $ARGOCD app list"
