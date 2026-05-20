#!/usr/bin/env bash
set -euo pipefail

# Day-0: Terraform installs Argo CD; day-1: apply root Application from gitops/
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV="${ENV:-local-kind}"

echo "==> Terraform bootstrap (Argo CD install)"
cd "${ROOT}/infra/environments/${ENV}"
terraform init
terraform apply -auto-approve -target=module.argocd_bootstrap

echo "==> Apply GitOps root application"
kubectl apply -f "${ROOT}/gitops/bootstrap/root-app.yaml"

echo "Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
