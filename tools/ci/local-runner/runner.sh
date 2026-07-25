#!/usr/bin/env bash
set -euo pipefail

# Manage the local GitHub self-hosted runner (docker compose) and dispatch CI
# workflows to it. The runner executes the repo's real GitHub Actions
# workflows on the host, so every workflow command here mirrors act-runner.sh
# but goes through the actual CI (gh workflow run) instead of a local act
# container.
#
# Usage:
#   runner.sh {up|down|logs}                                  Runner container lifecycle
#   runner.sh {apply|ci|base|middleware|workload|destroy|destroy-force}
#                                                              Dispatch the corresponding workflow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/docker-compose.yml"
REPO="aldoshkineg/atlas-idp"

require_gh() {
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI not found" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated (run 'gh auth login')" >&2; exit 1; }
}

# Resolve the active ref so the dispatched workflow runs from the current
# branch (falls back to main when in a detached HEAD state).
current_ref() {
  git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

dispatch() {
  require_gh
  local wf="$1"; shift
  gh workflow run "$wf" --repo "$REPO" --ref "$(current_ref)" "$@"
}

case "${1:-}" in
  up)     ( cd "$SCRIPT_DIR" && ./setup-runner.sh ) ;;
  down)   docker compose -f "$COMPOSE" down ;;
  logs)   docker compose -f "$COMPOSE" logs -f ;;

  # Workflow dispatch — mirrors act-runner.sh capabilities.
  apply)          dispatch ci-base.yaml ;;
  ci)             dispatch ci-all.yaml ;;
  base)           dispatch ci-base.yaml ;;
  middleware)     dispatch ci-middleware.yaml ;;
  workload)       dispatch ci-workload.yaml ;;
  destroy)        dispatch ci-destroy.yaml -f confirm=destroy ;;
  destroy-force)  dispatch ci-destroy-force.yaml ;;

  *) echo "Usage: runner.sh {up|down|logs|apply|ci|base|middleware|workload|destroy|destroy-force}" >&2; exit 1 ;;
esac
