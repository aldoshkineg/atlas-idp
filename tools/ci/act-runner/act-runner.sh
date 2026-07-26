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
  rm -f "$ACT_RUNNER_DIR/install-tools.sh" "$ACT_RUNNER_DIR/requirements.md"
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
  # no arguments. Drop the script and the version table (docs/requirements.md,
  # the single source of truth) into the build context.
  cp "$INSTALL_TOOLS" "$ACT_RUNNER_DIR/install-tools.sh"
  cp "$REPO_ROOT/docs/requirements.md" "$ACT_RUNNER_DIR/requirements.md"

  docker build -t act-runner:latest "$ACT_RUNNER_DIR"
}

run_workflow() {
  local wf="$1"; shift

  # Only the custom act-runner image is required for workflows that run on it.
  # Workflows on GitHub-hosted runners (e.g. ubuntu-latest) use act's default
  # image and can run without act-runner:latest being built locally.
  if grep -qE "runs-on:[[:space:]]*act-runner" "$wf"; then
    if ! docker image inspect act-runner:latest &>/dev/null; then
      echo "act-runner:latest not found. Run 'make act-build' or 'act-runner.sh build' first." >&2
      exit 1
    fi
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
     -s ENV_FILE="$(cat "$REPO_ROOT/.env" 2>/dev/null || true)" \
    -s GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    "$@"
}

# `act` (0.2.89) cannot run ci-all.yaml because it uses reusable workflows
# (`uses: ./.github/workflows/ci-*.yaml`), which act's schema validator rejects.
# GitHub-native runners (make ci-runner-ci) handle that fine, so the real
# ci-all orchestration is tested there. For the local `act` path we replicate
# ci-all's job order (base -> middleware -> workload) by running the three
# component workflows sequentially — the same jobs, executed locally.
run_ci_pipeline() {
  run_workflow "$REPO_ROOT/.github/workflows/ci-base.yaml" "$@"
  run_workflow "$REPO_ROOT/.github/workflows/ci-middleware.yaml" "$@"
  run_workflow "$REPO_ROOT/.github/workflows/ci-workload.yaml" "$@"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  build)
    build
    ;;

  ci)
    run_ci_pipeline "$@"
    ;;

  # `apply` mirrors runner.sh: run only the base stage (infra + vault seeds).
  apply)
    run_workflow "$REPO_ROOT/.github/workflows/ci-base.yaml" "$@"
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

  # Run the unit-test workflows (test-seal, test-atlasctl) via act. They run on
  # ubuntu-latest; locally we map that to the act-runner image (which carries
  # curl/unzip) so the install-tools step works under act. test-platform requires
  # a live cluster (self-hosted) and is excluded here.
  test)
    run_workflow "$REPO_ROOT/.github/workflows/test-seal.yaml" -P ubuntu-latest=act-runner:latest "$@"
    run_workflow "$REPO_ROOT/.github/workflows/test-atlasctl.yaml" -P ubuntu-latest=act-runner:latest "$@"
    ;;

  *)
    echo "Usage: $0 {build|ci|base|middleware|workload|destroy|destroy-force|test}"
    exit 1
    ;;
esac
