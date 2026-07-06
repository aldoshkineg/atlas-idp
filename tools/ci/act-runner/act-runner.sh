#!/bin/bash
set -euo pipefail

ACT_RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
if git -C "$ACT_RUNNER_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$ACT_RUNNER_DIR" rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$ACT_RUNNER_DIR/../../.." && pwd)"
fi

ACTION_YML="$REPO_ROOT/.github/actions/tools/action.yml"
INSTALL_TOOLS="$REPO_ROOT/.github/scripts/install-tools.sh"
INSTALL_CMD_LIST="/tmp/act-runner-install-cmds.sh"
INSTALL_TOOLS_COPY="/tmp/act-runner-install-tools.sh"

CACHE_DIR="/var/tmp/atlas/act_cache"

cleanup() {
  rm -f "$INSTALL_CMD_LIST" "$INSTALL_TOOLS_COPY" \
        "$ACT_RUNNER_DIR/install-cmds.sh" "$ACT_RUNNER_DIR/install-tools.sh"
}
trap cleanup EXIT

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

build() {
  require_file "$ACTION_YML"
  require_file "$INSTALL_TOOLS"

  cp "$INSTALL_TOOLS" "$INSTALL_TOOLS_COPY"

  declare -A TOOL_VARS=(
    [vault]=VAULT_VERSION
    [terraform]=TERRAFORM_VERSION
    [kubectl]=KUBECTL_VERSION
    [kind]=KIND_VERSION
    [trivy]=TRIVY_VERSION
    [yamllint]=YAMLLINT_VERSION
  )

  for tool in "${!TOOL_VARS[@]}"; do
    ver=$(grep -F "${TOOL_VARS[$tool]}:" "$ACTION_YML" | awk '{print $2}' | tr -d '"')
    echo "install-tools.sh $tool $ver"
  done > "$INSTALL_CMD_LIST"

  cp "$INSTALL_TOOLS_COPY" "$ACT_RUNNER_DIR/install-tools.sh"
  cp "$INSTALL_CMD_LIST" "$ACT_RUNNER_DIR/install-cmds.sh"

  docker build -t act-runner:latest "$ACT_RUNNER_DIR"
}

run_ci() {
  shift
  require_file "$REPO_ROOT/security/certs/ca.crt"
  require_file "$REPO_ROOT/security/certs/ca.key"
  require_file "$REPO_ROOT/.env"

  if ! docker image inspect act-runner:latest &>/dev/null; then
    echo "act-runner:latest not found. Run 'make act-build' or 'act-runner.sh build' first." >&2
    exit 1
  fi

  mkdir -p "$CACHE_DIR/tf" "$CACHE_DIR/home" /var/tmp/atlas

  source "$REPO_ROOT/.env"

  act -W "$REPO_ROOT/.github/workflows/ci.yaml" \
    --container-options "-v $CACHE_DIR/tf:/opt/terraform/plugin-cache -v $CACHE_DIR/home:/root -v /var/tmp/atlas:/var/tmp/atlas -v /var/lib/incus/unix.socket:/var/lib/incus/unix.socket" \
    -s ATLAS_CA_CRT="$(cat "$REPO_ROOT/security/certs/ca.crt")" \
    -s ATLAS_CA_KEY="$(cat "$REPO_ROOT/security/certs/ca.key")" \
    -s VAULT_TOKEN="${VAULT_TOKEN:-}" \
    -s VL_MINIO_ROOT_USER="${VL_MINIO_ROOT_USER:-}" \
    -s VL_MINIO_ROOT_PASSWORD="${VL_MINIO_ROOT_PASSWORD:-}" \
    -s VL_REDIS_PASSWORD="${VL_REDIS_PASSWORD:-}" \
    -s VL_GRAFANA_PASSWORD="${VL_GRAFANA_PASSWORD:-}" \
    "$@"
}

case "${1:-}" in
  build)
    build
    ;;

  ci)
    run_ci "$@"
    ;;

  *)
    echo "Usage: $0 {build|ci}"
    exit 1
    ;;
esac
