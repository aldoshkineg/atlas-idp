#!/usr/bin/env bash
#
# sync-layers.sh — sequentially sync ArgoCD layers after a fresh stage
# deploy. Split into phases so the platform middleware can stabilize before
# the workloads are seeded and synced.
#
# Phases:
#   all        (default) sync platform layers, seed workloads, sync workloads
#   middleware sync only the platform layers (storage/security/delivery/
#              observability) — brings up postgres/minio/vault/monitoring
#   workloads  seed enabled workloads (atlasctl) then sync the workloads layer
#              — run AFTER the middleware phase so its ExternalSecrets find
#              their Vault secrets already provisioned (Ready, not Degraded)
#
# root-app is Automated, but child layer apps are Manual, so they need an
# explicit sync. A settle delay lets dependencies come up first. The settle
# is skipped only when a layer was already Synced+Healthy BEFORE this run
# (idempotent re-sync of a healthy cluster stays fast); fresh/partial deploys
# still wait.
#
# Usage:
#   ./tools/ci/sync-layers.sh [all|middleware|workloads]
#
# Env:
#   KUBECONFIG  (default /var/tmp/atlas/talos/kubeconfig)
#   SETTLE_SECS (default 60; settle is skipped when a layer is already healthy)

set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/var/tmp/atlas/talos/kubeconfig}"
SETTLE_SECS="${SETTLE_SECS:-60}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PHASE="${1:-all}"
case "${PHASE}" in
  all|middleware|workloads) ;;
  *) echo "Unknown phase '${PHASE}'. Use: all | middleware | workloads" >&2; exit 1 ;;
esac

# Platform (middleware) layers. The workloads layer is synced separately in
# the `workloads` phase, AFTER seeding, so its ExternalSecrets find their Vault
# secrets already present — storage brings up postgres/minio/vault that seed
# provisions against (DB users, buckets, Vault secrets).
LAYERS=(storage security delivery observability)

log() { echo "==> $*"; }

log "Phase: ${PHASE}"

# Preflight: the CLIs below are required. Without them every `argocd app sync`
# silently fails (command not found) while the loop swallows the error, so the
# job would report success on an empty cluster. Fail fast instead.
for bin in argocd kubectl; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${bin}' not found in PATH — install it (see .github/actions/tools) before running." >&2
    exit 1
  fi
done

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

# Return "<sync> <health>" for a layer app, or empty if not found.
# `argocd app list` prints the name as NAMESPACE/NAME (e.g. argocd/storage)
# and columns: $1=NAME $2=CLUSTER $3=NAMESPACE $4=PROJECT $5=STATUS $6=HEALTH.
layer_state() {
  argocd app list 2>/dev/null | awk -v app="$1" '
    $1 == ("argocd/" app) || $1 == app { print $5, $6; exit }
  '
}

if [[ "${PHASE}" == "all" || "${PHASE}" == "middleware" ]]; then
  for layer in "${LAYERS[@]}"; do
    # Capture state BEFORE syncing. A fresh/partial deploy (layer not yet
    # Healthy) must still settle so dependencies (postgres/minio/vault) come
    # up before the next layer. We only skip the settle when the layer was
    # already Synced+Healthy before this run — i.e. an idempotent re-sync of a
    # healthy cluster, which should be instant. Checking the post-sync state
    # would be unsafe: ArgoCD can report Healthy for custom CRDs (e.g. DB
    # clusters) before the underlying pods are actually Ready.
    pre="$(layer_state "${layer}")"
    sync_layer "${layer}"
    if [[ "${pre}" == "Synced Healthy" ]]; then
      log "[${layer}] was already Synced/Healthy — skipping settle."
      continue
    fi
    log "[${layer}] settling ${SETTLE_SECS}s for dependencies to become Ready..."
    sleep "${SETTLE_SECS}"
  done
fi

# --- Seed workloads, then sync the workloads layer ---
# The platform loop above brought up PostgreSQL / MinIO / Vault. seed provisions
# per-workload DB users, buckets and Vault secrets. Running it BEFORE the
# workloads sync means ExternalSecrets come up Ready instead of Degraded.
# (Skipped gracefully if atlasctl/jq are unavailable, e.g. local runs.)
if [[ "${PHASE}" == "all" || "${PHASE}" == "workloads" ]]; then
  if ! command -v atlasctl >/dev/null 2>&1; then
    log "atlasctl not found — skipping seed (run 'make atlasctl-build' locally)."
  elif ! command -v jq >/dev/null 2>&1; then
    log "jq not found — skipping seed."
  else
    log "Seeding enabled workloads..."
    for wl in $(atlasctl list --json | jq -r '.[] | select(.enabled) | .name'); do
      log "  seeding ${wl}"
      atlasctl seed "${wl}" -y
    done
  fi

  # Now sync the workloads layer (ExternalSecrets already seeded → Ready).
  pre_wl="$(layer_state "workloads")"
  sync_layer "workloads"
  if [[ "${pre_wl}" == "Synced Healthy" ]]; then
    log "[workloads] was already Synced/Healthy — skipping settle."
  else
    log "[workloads] settling ${SETTLE_SECS}s for pods to become Ready..."
    sleep "${SETTLE_SECS}"
  fi
fi

  # --- Health gate: fail the job if any targeted layer is not Synced/Healthy ---
  # Previously sync_layer swallowed errors (|| true / "continuing"), so a red CI
  # run could hide a broken deploy. Now we fail the job when a layer is not
  # Synced or sits in a bad health state, so green actually means healthy.
  health_ok() {
    local st="$1"
    local status="${st%% *}"
    local health="${st##* }"
    [ "$status" = "Synced" ] || return 1
    case "$health" in
      Degraded|Missing|Failed|Suspended|Unknown|"") return 1 ;;
    esac
    return 0
  }

  gate_layers=()
  if [[ "${PHASE}" == "all" || "${PHASE}" == "middleware" ]]; then
    gate_layers+=("${LAYERS[@]}")
  fi
  if [[ "${PHASE}" == "all" || "${PHASE}" == "workloads" ]]; then
    gate_layers+=("workloads")
  fi

  gate_failed=0
  for layer in "${gate_layers[@]}"; do
    st="$(layer_state "${layer}")"
    if health_ok "$st"; then
      log "[${layer}] healthy (${st})"
    else
      echo "❌ [${layer}] NOT healthy: '${st}'" >&2
      gate_failed=1
    fi
  done
  if [[ "${gate_failed}" -ne 0 ]]; then
    echo "Health gate FAILED — one or more layers are not Synced/Healthy." >&2
    exit 1
  fi

  log "Final status:"
  argocd app list | awk 'NR==1 || $4!="Synced" || $5!="Healthy"{print}'

  log "Done. Verify with: argocd app list"
