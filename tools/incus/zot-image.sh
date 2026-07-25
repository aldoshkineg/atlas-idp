#!/usr/bin/env bash
set -euo pipefail

# Manage the Zot OCI pull-through cache image/instance in Incus.
#
# Usage:
#   zot-image.sh ensure
#     Ensure the 'zot-cache' image alias exists (copy from ghcr if missing)
#
# Environment:
#   ZOT_REMOTE      Incus remote name   (default: ghcr-oci)
#   ZOT_IMAGE_REF   Source image ref    (default: ghcr.io/project-zot/zot:v2.1.16)
#   ZOT_IMAGE_ALIAS Incus alias to use  (default: zot-cache)
#   ZOT_CACHE_DIR   Host cache path     (default: /var/tmp/atlas/zot_cache)

ZOT_REMOTE="${ZOT_REMOTE:-ghcr-oci}"
ZOT_IMAGE_REF="${ZOT_IMAGE_REF:-ghcr.io/project-zot/zot:v2.1.16}"
ZOT_IMAGE_ALIAS="${ZOT_IMAGE_ALIAS:-zot-cache}"
ZOT_CACHE_DIR="${ZOT_CACHE_DIR:-/var/tmp/atlas/zot_cache}"

ensure() {
  echo "--> Ensuring Zot image '${ZOT_IMAGE_ALIAS}' is present in Incus..."
  if ! command -v incus >/dev/null 2>&1; then
    echo "ERROR: incus CLI not found" >&2
    exit 1
  fi
  incus remote list 2>/dev/null | grep -qw "${ZOT_REMOTE}" || \
    incus remote add "${ZOT_REMOTE}" https://ghcr.io --protocol oci --public
  if incus image list 2>/dev/null | grep -qw "${ZOT_IMAGE_ALIAS}"; then
    echo "    '${ZOT_IMAGE_ALIAS}' already present, skipping copy"
  else
    echo "    copying ${ZOT_IMAGE_REF} ..."
    incus image copy "${ZOT_REMOTE}:project-zot/zot:v2.1.16" --alias "${ZOT_IMAGE_ALIAS}"
  fi
}

case "${1:-ensure}" in
  ensure) ensure ;;
  *) echo "Unknown command: ${1:-} (use ensure)" >&2; exit 1 ;;
esac
