#!/usr/bin/env bash
#
# sync-layers.sh — sequentially sync all ArgoCD platform layers after a
# fresh `make act-stage-apply`. root-app is Automated, but child layers
# (storage/security/delivery/observability/workloads) are Manual, so they
# need an explicit sync. Each layer is synced with a 60s settle delay so
# that dependencies (e.g. postgres/minio/vault for workloads) come up first.
#
# Usage:
#   ./clusters/scripts/sync-layers.sh
#
# Env:
#   KUBECONFIG  (default /var/tmp/atlas/talos/kubeconfig)
#   SETTLE_SECS (default 60)

set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/var/tmp/atlas/talos/kubeconfig}"
SETTLE_SECS="${SETTLE_SECS:-60}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Layers in dependency order. workloads must be last (needs storage + delivery).
LAYERS=(storage security delivery observability workloads)

log() { echo "==> $*"; }

# Login to ArgoCD (installs/configures context via tools/argocd-login.sh)
log "Logging into ArgoCD..."
"${REPO_ROOT}/tools/argocd-login.sh" >/dev/null

# Kick off root-app first so all Application objects are created/updated.
log "Syncing root-app (creates/updates layer Application objects)..."
argocd app sync root-app --force || true

sync_layer() {
  local layer="$1"
  local attempt
  for attempt in 1 2 3; do
    log "[${layer}] sync attempt ${attempt}/3..."
    if argocd app sync "${layer}" --force; then
      return 0
    fi
    # "operation in progress" or transient error — wait and retry
    sleep 15
  done
  echo "⚠️  [${layer}] sync did not complete cleanly; continuing."
  return 0
}

for layer in "${LAYERS[@]}"; do
  sync_layer "${layer}"
  log "[${layer}] settling ${SETTLE_SECS}s for dependencies to become Ready..."
  sleep "${SETTLE_SECS}"
done

log "Final status:"
argocd app list | awk 'NR==1 || $4!="Synced" || $5!="Healthy"{print}'

log "Done. Verify with: argocd app list"
