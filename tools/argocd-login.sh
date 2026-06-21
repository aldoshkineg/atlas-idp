#!/usr/bin/env bash

set -eo pipefail

kind export kubeconfig --name atlas-idp

ARGOCD_SERVER="argocd.atlas"
ARGOCD_USER="admin"
SECRET_NAME="argocd-initial-admin-secret"
NAMESPACE="argocd"

echo "==> Fetching admin password..."
if ! ARGOCD_PASSWORD=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode); then
    echo "⚠️  Failed to fetch password from kubectl. Please enter it manually:"
    read -rs ARGOCD_PASSWORD
fi

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "❌ Error: Password cannot be empty."
    exit 1
fi

echo "==> Logging into ArgoCD CLI..."
if argocd login "$ARGOCD_SERVER" --username "$ARGOCD_USER" --password "$ARGOCD_PASSWORD" --grpc-web; then
    echo "✅ Login successful."
else
    echo "❌ Error: ArgoCD login failed."
    exit 1
fi
