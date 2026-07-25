#!/bin/bash
# Initialize a Terraform working directory with a retry loop.
# Used by the terraform and destroy workflows so the init logic lives in one place.
set -euo pipefail

cd "${1:-.}"

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/opt/terraform/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

n=0
until [ "$n" -ge 3 ]; do
  terraform init -reconfigure && break
  n=$((n + 1))
  echo "Terraform init failed. Retry $n/3"
  sleep 15
done
[ "$n" -lt 3 ] || exit 1
