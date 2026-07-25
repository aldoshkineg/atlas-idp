#!/usr/bin/env bash
set -euo pipefail

# Verify Seal image signatures (cosign) for api/worker/ui.
#
# Usage:
#   seal-verify.sh [TAG]
#
# The tag is resolved automatically when not given:
#   - explicit TAG=<x> or first arg wins,
#   - otherwise the latest git tag (vX.Y.Z) of this repo is used. Seal images
#     are built and pushed by the CI workflow (.github/workflows/
#     seal-docker-publish.yml) using `type=ref,event=tag`, so the repo tag is
#     the source of truth for the published image version.
#
# Environment:
#   TAG  Image tag to verify (overrides auto-resolution)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEY="${ROOT_DIR}/security/cosign/cosign.pub"

SERVICES="seal-api seal-worker seal-ui"
REGISTRY="ghcr.io/aldoshkineg"

[ -f "$KEY" ] || { echo "ERROR: cosign public key not found: $KEY" >&2; exit 1; }
command -v cosign >/dev/null 2>&1 || { echo "ERROR: cosign not in PATH" >&2; exit 1; }

# Latest git tag of this repo (vX.Y.Z). Seal images are published from the
# same tag via the docker-publish workflow, so this is the canonical version.
resolve_tag() {
  git -C "$ROOT_DIR" describe --tags --match='v[0-9]*' --abbrev=0 2>/dev/null
}

TAG="${1:-${TAG:-}}"
if [ -z "$TAG" ]; then
  echo "--> No TAG given, resolving latest git tag..."
  TAG="$(resolve_tag)"
  [ -n "$TAG" ] || { echo "ERROR: could not resolve a git tag (run inside the repo or pass TAG=)" >&2; exit 1; }
  echo "--> Resolved tag: ${TAG}"
fi

echo "--> Verifying Seal image signatures (tag: ${TAG})"
for svc in $SERVICES; do
  cosign verify --key "$KEY" --insecure-ignore-tlog "${REGISTRY}/${svc}:${TAG}" || exit 1
done
