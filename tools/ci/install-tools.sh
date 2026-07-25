#!/bin/bash
# install-tools.sh — bootstrap the CLI toolchain for Atlas IDP.
#
# Why it exists:
#   Both CI (the GitHub Actions `tools` composite action and the local act-runner
#   image) and local development need an identical, pinned set of CLIs
#   (vault, terraform, kubectl, trivy, yamllint, incus, argocd, atlasctl, xorriso).
#   This script is the single source of truth: the pinned versions live in
#   VERSION_MAP below, and one invocation installs the requested subset — or
#   everything when called with no arguments. Idempotent: a tool already on PATH
#   is skipped.
#
# Usage:
#   ./install-tools.sh                 # install all pinned tools
#   ./install-tools.sh trivy yamllint  # install a subset
#   ./install-tools.sh --version trivy # print the pinned version (no install)
#
# We intentionally support a single version per tool (no side-by-side installs).

set -eo pipefail

# --- Pinned versions (single source of truth) -------------------------------
declare -A VERSION_MAP=(
  [vault]="1.18.0"
  [terraform]="1.15.3"
  [kubectl]="1.34.0"
  [trivy]="0.70.0"
  [yamllint]="1.35.1"
  [incus]="7.2.0"
  [argocd]="3.4.2"
  [atlasctl]="0.60.0"
)
# xorriso is a system package (no pinned version) — required by the incus module
# to build the cloud-init seed ISO (`xorriso -as mkisofs ... -V cidata`).

# Subcommand: print the pinned version for a tool WITHOUT installing it. Used by
# workflows (e.g. security.yaml) that install a tool themselves but still want a
# single source of truth for the version. `install-tools.sh --version trivy` → 0.70.0
if [ "$1" = "--version" ]; then
  _tool="${2:-}"
  if [ -z "${VERSION_MAP[$_tool]:-}" ]; then
    echo "install-tools.sh: no pinned version for '$_tool'" >&2
    exit 1
  fi
  printf '%s\n' "${VERSION_MAP[$_tool]}"
  exit 0
fi

install_one() {
  local TOOL="$1"
  local VERSION="${VERSION_MAP[$TOOL]:-}"

  if command -v "$TOOL" &>/dev/null; then
    echo "$TOOL already installed ($(command -v "$TOOL"))"
    return 0
  fi

  echo "Installing $TOOL ${VERSION:+v$VERSION}"

  case "$TOOL" in
    vault)
      curl -fsSL \
        "https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_linux_amd64.zip" \
        -o vault.zip
      unzip -p vault.zip vault | sudo tee /usr/local/bin/vault > /dev/null
      sudo chmod +x /usr/local/bin/vault
      ;;

    terraform)
      curl -fsSL \
        "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip" \
        -o terraform.zip
      unzip -o terraform.zip
      sudo mv terraform /usr/local/bin/
      ;;

    kubectl)
      curl -LO \
        "https://dl.k8s.io/release/v${VERSION}/bin/linux/amd64/kubectl"
      chmod +x kubectl
      sudo mv kubectl /usr/local/bin/
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
      sudo mv incus /usr/local/bin/
      ;;

    argocd)
      curl -fsSL -o argocd \
        "https://github.com/argoproj/argo-cd/releases/download/v${VERSION}/argocd-linux-amd64"
      chmod +x argocd
      sudo mv argocd /usr/local/bin/
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
      sudo mv atlasctl /usr/local/bin/
      ;;

    xorriso)
      # System package (no pinned version).
      sudo apt-get update
      sudo apt-get install -y --no-install-recommends xorriso
      ;;

    *)
      echo "Unknown tool: $TOOL"
      exit 1
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- "${!VERSION_MAP[@]}" xorriso
fi

for tool in "$@"; do
  install_one "$tool"
done
