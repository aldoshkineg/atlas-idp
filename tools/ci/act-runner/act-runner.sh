#!/bin/bash
set -euo pipefail

ACT_RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
if git -C "$ACT_RUNNER_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$ACT_RUNNER_DIR" rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$ACT_RUNNER_DIR/../../.." && pwd)"
fi

INSTALL_TOOLS="$REPO_ROOT/tools/ci/install-tools.sh"

CACHE_DIR="/var/tmp/atlas/act_cache"

cleanup() {
  rm -f "$ACT_RUNNER_DIR/install-tools.sh"
}
trap cleanup EXIT

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

build() {
  require_file "$INSTALL_TOOLS"

  # The install script carries its own pinned versions (tools/ci/install-tools.sh);
  # the act-runner image installs the full toolchain via `install-tools.sh` with
  # no arguments. Just drop the script into the build context.
  cp "$INSTALL_TOOLS" "$ACT_RUNNER_DIR/install-tools.sh"

  docker build -t act-runner:latest "$ACT_RUNNER_DIR"
}

run_workflow() {
  local wf="$1"; shift

  if ! docker image inspect act-runner:latest &>/dev/null; then
    echo "act-runner:latest not found. Run 'make act-build' or 'act-runner.sh build' first." >&2
    exit 1
  fi

  mkdir -p "$CACHE_DIR/tf" "$CACHE_DIR/home" /var/tmp/atlas

  # Collect secrets: .env (Vault seeds + CA/cosign base64) plus .secrets
  # (GITHUB_TOKEN for act rate-limit / gh CLI).
  source "$REPO_ROOT/.env" 2>/dev/null || true
  source "$REPO_ROOT/.secrets" 2>/dev/null || true

  # Single ENV_FILE secret replayed by the ci-base "Load ENV_FILE" step, which
  # exports every var and materialises the CA cert/key. GITHUB_TOKEN is passed
  # separately (it is intentionally excluded from ENV_FILE / $GITHUB_ENV).
  #
  # Event selection: act defaults to "push", but the stage workflows only
  # listen on workflow_dispatch (+workflow_call), so a bare `act -W` finds no
  # jobs. Pick workflow_dispatch when the workflow declares it, otherwise fall
  # back to push (e.g. ci-all).
  local event="push"
  if grep -qE "^[[:space:]]*workflow_dispatch:[[:space:]]*$" "$wf"; then
    event="workflow_dispatch"
  fi

  act "$event" -W "$wf" \
    --container-options "-v $CACHE_DIR/tf:/opt/terraform/plugin-cache -v $CACHE_DIR/home:/root -v /var/tmp/atlas:/var/tmp/atlas -v /var/lib/incus/unix.socket:/var/lib/incus/unix.socket" \
    -s ENV_FILE="$(cat "$REPO_ROOT/.env")" \
    -s GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    "$@"
}

run_ci() {
  run_workflow "$REPO_ROOT/.github/workflows/ci-all.yaml" "$@"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  build)
    build
    ;;

  ci|apply)
    run_ci "$@"
    ;;

  base)
    run_workflow "$REPO_ROOT/.github/workflows/ci-base.yaml" "$@"
    ;;

  middleware)
    run_workflow "$REPO_ROOT/.github/workflows/ci-middleware.yaml" "$@"
    ;;

  workload)
    run_workflow "$REPO_ROOT/.github/workflows/ci-workload.yaml" "$@"
    ;;

  destroy)
    run_workflow "$REPO_ROOT/.github/workflows/ci-destroy.yaml" --input confirm=destroy "$@"
    ;;

  destroy-force)
    run_workflow "$REPO_ROOT/.github/workflows/ci-destroy-force.yaml" "$@"
    ;;

  *)
    echo "Usage: $0 {build|ci|base|middleware|workload|destroy|destroy-force}"
    exit 1
    ;;
esac
