#!/bin/bash
# install-tools.sh — bootstrap the CLI toolchain for Atlas IDP.
#
# Why it exists:
#   Both CI (the GitHub Actions `tools` composite action and the local act-runner
#   image) and local development need an identical, pinned set of CLIs
#   (vault, terraform, kubectl, trivy, yamllint, incus, argocd, atlasctl, xorriso).
#   Pinned versions are NOT defined here — they are read from
#   `docs/requirements.md` (the `## Local CLI Tooling` table), the single source
#   of truth shared with `preflight.sh`. This script only decides WHAT to
#   install and HOW. Idempotent: a tool already on PATH is skipped.
#
# Usage:
#   ./install-tools.sh                 # install all pinned tools
#   ./install-tools.sh trivy yamllint  # install a subset
#   ./install-tools.sh --version trivy # print the pinned version (no install)
#
# We intentionally support a single version per tool (no side-by-side installs).

set -eo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# --- Versions: read from docs/requirements.md (single source of truth) ------
REQ_FILE="$REPO_ROOT/docs/requirements.md"
if [ ! -f "$REQ_FILE" ]; then
  echo "install-tools.sh: $REQ_FILE not found" >&2
  exit 1
fi

# Resolve the pinned version for a tool from the `## Local CLI Tooling` table.
# Mirrors the parser in tools/ci/preflight.sh. Prints the version and returns 0;
# prints nothing and returns 1 if the tool is absent (e.g. system packages).
req_version() {
  local tool="$1" row ver
  row="$(awk '/^## Local CLI Tooling/{f=1;next} /^## /{if(f)exit} f' "$REQ_FILE" \
          | grep '^|' \
          | awk -F'|' -v t="$tool" 'NR>2 { gsub(/^[ \t]+|[ \t]+$/,"",$2); if($2==t){gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3; exit} }')"
  ver="$(printf '%s' "$row" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -n "$ver" ]; then printf '%s\n' "$ver"; return 0; fi
  return 1
}

# Tools this script knows how to install (the WHAT). Versions come from REQ_FILE.
# xorriso is a system package (no pinned version) required by the incus module
# to build the cloud-init seed ISO (`xorriso -as mkisofs ... -V cidata`).
INSTALL_TOOLS=(vault terraform kubectl trivy yamllint incus argocd velero atlasctl xorriso)

# Subcommand: print the pinned version for a tool WITHOUT installing it. Used by
# workflows (e.g. security.yaml) that install a tool themselves but still want a
# single source of truth for the version. `install-tools.sh --version trivy` → 0.70.0
if [ "$1" = "--version" ]; then
  _tool="${2:-}"
  if _ver="$(req_version "$_tool")"; then
    printf '%s\n' "$_ver"
  else
    echo "install-tools.sh: no pinned version for '$_tool' in $REQ_FILE" >&2
    exit 1
  fi
  exit 0
fi

install_one() {
  local TOOL="$1"
  local VERSION=""
  VERSION="$(req_version "$TOOL" || true)"
  local BIN="$TOOL"
  case "$TOOL" in
    go-task) BIN=task ;;
  esac

  # Elevate only when not already root (GitHub-hosted runner). The act-runner
  # image runs as root with $SUDO stripped, and local act containers run as root,
  # so this stays empty there.
  local SUDO=""
  if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

  if command -v "$BIN" &>/dev/null; then
    echo "$TOOL already installed ($(command -v "$BIN"))"
    return 0
  fi

  echo "Installing $TOOL ${VERSION:+v$VERSION}"

  case "$TOOL" in
    vault)
      curl -fsSL \
        "https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_linux_amd64.zip" \
        -o vault.zip
      unzip -p vault.zip vault | $SUDO tee /usr/local/bin/vault > /dev/null
      $SUDO chmod +x /usr/local/bin/vault
      ;;

    terraform)
      curl -fsSL \
        "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip" \
        -o terraform.zip
      unzip -o terraform.zip
      $SUDO mv terraform /usr/local/bin/
      ;;

    kubectl)
      curl -LO \
        "https://dl.k8s.io/release/v${VERSION}/bin/linux/amd64/kubectl"
      chmod +x kubectl
      $SUDO mv kubectl /usr/local/bin/
      ;;

    trivy)
      # BIN_DIR lets callers install to a writable dir (e.g. a CI cache dir)
      # without sudo; defaults to /usr/local/bin for local/dev use.
      BIN_DIR="${BIN_DIR:-/usr/local/bin}"
      mkdir -p "$BIN_DIR"
      if [ -w "$BIN_DIR" ]; then SUDO=""; else SUDO="sudo"; fi
      echo "Installing trivy v${VERSION} into ${BIN_DIR}"
      curl -sfL \
        https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh |
        $SUDO sh -s -- -b "$BIN_DIR" v"${VERSION}"
      [ -x "$BIN_DIR/trivy" ] || { echo "trivy install failed"; exit 1; }
      ;;

    yamllint)
      pip install "yamllint==${VERSION}"
      ;;

    incus)
      curl -fsSL -o incus \
        "https://github.com/lxc/incus/releases/download/v${VERSION}/bin.linux.incus.x86_64"
      chmod +x incus
      $SUDO mv incus /usr/local/bin/
      ;;

    argocd)
      curl -fsSL -o argocd \
        "https://github.com/argoproj/argo-cd/releases/download/v${VERSION}/argocd-linux-amd64"
      chmod +x argocd
      $SUDO mv argocd /usr/local/bin/
      ;;

    atlasctl)
      case "$(uname -m)" in
        x86_64)  GOARCH=amd64 ;;
        aarch64) GOARCH=arm64 ;;
        *)       echo "Unsupported arch for atlasctl: $(uname -m)"; exit 1 ;;
      esac
      curl -fsSL -o atlasctl \
        "https://github.com/aldoshkineg/atlas-idp/releases/download/v${VERSION}/atlasctl-linux-${GOARCH}"
      chmod +x atlasctl
      $SUDO mv atlasctl /usr/local/bin/
      ;;

    xorriso)
      # System package (no pinned version).
      $SUDO apt-get update
      $SUDO apt-get install -y --no-install-recommends xorriso
      ;;

    jq)
      # System package (no pinned version) — used to parse argocd JSON output.
      $SUDO apt-get update
      $SUDO apt-get install -y --no-install-recommends jq
      ;;

    go-task)
      # go-task (task) — pinned via docs/requirements.md (Local CLI Tooling).
      curl -fsSL -o task.tgz \
        "https://github.com/go-task/task/releases/download/v${VERSION}/task_linux_amd64.tar.gz"
      tar -xzf task.tgz task
      $SUDO mv task /usr/local/bin/
      rm -f task.tgz
      ;;

    velero)
      # velero CLI — pinned via docs/requirements.md (Local CLI Tooling).
      curl -fsSL -o velero.tgz \
        "https://github.com/vmware-tanzu/velero/releases/download/v${VERSION}/velero-v${VERSION}-linux-amd64.tar.gz"
      tar -xzf velero.tgz
      $SUDO mv "velero-v${VERSION}-linux-amd64/velero" /usr/local/bin/
      rm -rf velero.tgz "velero-v${VERSION}-linux-amd64"
      ;;

    *)
      echo "Unknown tool: $TOOL"
      exit 1
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- "${INSTALL_TOOLS[@]}"
fi

for tool in "$@"; do
  install_one "$tool"
done
