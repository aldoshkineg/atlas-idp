#!/usr/bin/env bash
set -euo pipefail

# Run quality-assurance checks. Delegates to the actual tooling so the
# Makefile stays declarative.
#
# Usage:
#   validate.sh {terraform|yaml|security|all}
#
# Environment:
#   ENV                 Environment to validate Terraform for (default: stage)
#   TF_PLUGIN_CACHE_DIR Terraform plugin cache (default: /var/tmp/atlas/act_cache/tf)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/var/tmp/atlas/act_cache/tf}"
ENV="${ENV:-stage}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

run_terraform() {
  echo "==> Running Terraform format check..."
  terraform fmt -check -recursive "${ROOT_DIR}/infra/"
  echo "==> Running Terraform validate..."
  ( cd "${ROOT_DIR}/infra/environments/${ENV}" && \
    TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR" terraform init -backend=false && \
    TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR" terraform validate )
}

run_yaml() {
  echo "==> Running YAML lint..."
  if command -v yamllint >/dev/null 2>&1; then
    yamllint -c "${ROOT_DIR}/.yamllint.yml" gitops/ observability/ security/ tests/
  else
    echo "yamllint not installed, skip"
  fi
}

run_security() {
  echo "==> Running security scan..."
  if command -v trivy >/dev/null 2>&1; then
    trivy config --config "${ROOT_DIR}/security/trivy/trivy.yaml" --severity HIGH,CRITICAL "${ROOT_DIR}/infra/"
    trivy config --config "${ROOT_DIR}/security/trivy/trivy.yaml" --severity HIGH,CRITICAL "${ROOT_DIR}/gitops/"
  else
    echo "trivy not installed, skip"
  fi
}

case "${1:-all}" in
  terraform) run_terraform ;;
  yaml)      run_yaml ;;
  security)  run_security ;;
  all)       run_terraform; run_yaml; run_security ;;
  *) echo "Usage: validate.sh {terraform|yaml|security|all}" >&2; exit 1 ;;
esac
