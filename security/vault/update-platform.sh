#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/seed-platform.sh" update

kubectl -n minio rollout restart statefulset/minio
kubectl -n redis rollout restart statefulset/redis-master
