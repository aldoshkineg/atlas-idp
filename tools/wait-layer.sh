#!/usr/bin/env bash
# Wait until every leaf Application of a layer reports Healthy.
#
# The layer wrapper Application is excluded: it is Manual and reports Healthy
# even when its children are broken, so it cannot be used as a readiness gate.
# Instead we select the layer's leaf apps by their Argo CD AppProject (which
# equals the layer name) and poll their health compactly.
#
# Apps in Degraded are treated as NOT ready: a Degraded app is a real problem
# (or is waiting on a downstream dependency that has not been deployed yet).
# To allow specific apps to stay non-Healthy, list them in the ALLOW_DEGRADED
# env var (space separated, without the "argocd/" prefix).
#
# Usage: wait-layer.sh <layer> [timeout-seconds]
set -euo pipefail

LAYER="${1:?usage: wait-layer.sh <layer> [timeout]}"
TIMEOUT="${2:-900}"
INTERVAL=10

# Apps whose non-Healthy state is tolerated for a given layer (known transient
# during bootstrap, or waiting on a downstream dependency not deployed by this
# layer). Env ALLOW_DEGRADED extends/overrides this per-layer default.
case "${LAYER}" in
  base) LAYER_ALLOW="platform-secrets" ;;
  *) LAYER_ALLOW="" ;;
esac
ALLOW_DEGRADED="$(echo "${ALLOW_DEGRADED:-} ${LAYER_ALLOW}" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' || true)"

elapsed=0
while true; do
  mapfile -t APPS < <(argocd app list -p "${LAYER}" --output json 2>/dev/null | python3 -c "
import sys, json
layer = '${LAYER}'
allow = set('${ALLOW_DEGRADED}'.split())
for a in json.load(sys.stdin):
    name = a['metadata']['name']
    if name == layer:
        continue
    st = a.get('status', {})
    health = st.get('health', {}).get('status', 'Unknown')
    sync = st.get('sync', {}).get('status', 'Unknown')
    state = 'allowed' if name in allow else health
    print(f'{name}\t{sync}\t{state}')
")
  if [ "${#APPS[@]}" -eq 0 ]; then
    echo "ERROR: no leaf applications found for layer '${LAYER}'."
    echo "       Argo CD may be unreachable, or the layer's child apps were pruned/deleted."
    exit 1
  fi
  ready=1
  for line in "${APPS[@]:-}"; do
    [ -z "$line" ] && continue
    h=$(printf '%s' "$line" | cut -f3)
    [ "$h" = "Healthy" ] || [ "$h" = "allowed" ] || ready=0
  done

  echo "[$(date +%H:%M:%S)] layer=${LAYER} elapsed=${elapsed}s"
  for line in "${APPS[@]:-}"; do
    [ -z "$line" ] && continue
    printf '  %s\n' "$(printf '%s' "$line" | tr '\t' '  ')"
  done

  if [ "$ready" -eq 1 ]; then
    echo "Layer '${LAYER}' is Ready (all leaf apps Healthy)."
    exit 0
  fi

  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "TIMEOUT: layer '${LAYER}' not Ready within ${TIMEOUT}s"
    exit 1
  fi

  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done
