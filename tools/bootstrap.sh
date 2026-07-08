#!/usr/bin/env bash
# Deploy platform layers in order, waiting for each to become Healthy before
# moving on to the next. Layers are deployed via `argocd app sync <layer>`
# (which triggers the layer's automated leaf apps) followed by wait-layer.sh.
#
# Usage: bootstrap.sh [start-layer] [timeout-seconds]
#   start-layer   layer to begin from (default: base). Earlier layers are skipped.
#   timeout       per-layer wait timeout in seconds (default: 900).
set -euo pipefail

LAYERS=(base storage security observability delivery workloads)
START="${1:-base}"
TIMEOUT="${2:-900}"

start_idx=-1
for i in "${!LAYERS[@]}"; do
  if [ "${LAYERS[$i]}" = "${START}" ]; then
    start_idx=$i
  fi
done

if [ "${start_idx}" -lt 0 ]; then
  echo "Unknown layer: ${START}" >&2
  echo "Valid layers: ${LAYERS[*]}" >&2
  exit 1
fi

for ((i = start_idx; i < ${#LAYERS[@]}; i++)); do
  L="${LAYERS[$i]}"
  echo "==> [$((i + 1))/${#LAYERS[@]}] Sync layer: ${L}"
  argocd app sync "${L}"
  echo "==> Wait for layer '${L}' to become Healthy"
  ./tools/wait-layer.sh "${L}" "${TIMEOUT}"
done

echo "All layers deployed and Healthy."
