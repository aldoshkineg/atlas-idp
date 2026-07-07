#!/usr/bin/env bash

set -eo pipefail

export KUBECONFIG="${KUBECONFIG:-/var/tmp/atlas/talos/kubeconfig}"
ARGOCD="argocd"
ARGOCD_SERVER="argocd.atlas"
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
if expect -c "
    set timeout 10
    spawn $ARGOCD login $ARGOCD_SERVER --username $ARGOCD_USER --password {$ARGOCD_PASSWORD} --insecure
    expect {
        \"Proceed\" { send \"y\r\"; exp_continue }
        \"logged in successfully\" { exit 0 }
        \"FATA\" { exit 1 }
        timeout { exit 1 }
        eof { exit 1 }
    }
" 2>/dev/null; then
    echo "✅ Login successful."
    echo "    Run: $ARGOCD app list"
else
    echo "❌ Error: ArgoCD login failed."
    exit 1
fi
