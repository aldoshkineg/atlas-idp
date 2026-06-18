#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_FILE="${1:-}"

if [ -z "$SEED_FILE" ] || [ ! -f "$SEED_FILE" ]; then
  echo "Usage: $0 <secrets-file>" >&2
  exit 1
fi

"$SCRIPT_DIR/seed-platform.sh" update "$SEED_FILE"

kubectl -n minio rollout restart statefulset/minio
kubectl -n redis rollout restart statefulset/redis-master
