#!/usr/bin/env bash
#
# Verify signatures of Seal container images with cosign.
#
# Usage:
#   ./verify.sh <tag> [service...]
#
# Examples:
#   ./verify.sh v0.25.0
#   ./verify.sh v0.25.0 seal-api seal-worker
#
# Requires cosign and the public key security/cosign/cosign.pub.

set -euo pipefail

TAG="${1:?usage: verify.sh <tag> [service...]}"
shift

SERVICES=("${@:-seal-api seal-worker seal-ui}")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${COSIGN_PUBLIC_KEY:-${SCRIPT_DIR}/cosign.pub}"
ORG="${COSIGN_ORG:-aldoshkineg}"

if ! command -v cosign >/dev/null 2>&1; then
  echo "error: cosign not found in PATH" >&2
  exit 1
fi

if [ ! -f "${KEY}" ]; then
  echo "error: public key not found: ${KEY}" >&2
  exit 1
fi

status=0
for svc in "${SERVICES[@]}"; do
  image="ghcr.io/${ORG}/${svc}:${TAG}"
  echo "==> Verifying ${image}"
  if cosign verify --key "${KEY}" "${image}"; then
    echo "OK: ${image}"
  else
    echo "FAIL: ${image}" >&2
    status=1
  fi
done

exit "${status}"
