#!/usr/bin/env bash
set -euo pipefail

kubectl -n vault wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=vault \
  --timeout=180s
