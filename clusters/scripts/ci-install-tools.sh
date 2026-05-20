#!/usr/bin/env bash
# Install kind + kubectl in CI job (docker:27-cli). Idempotent.
set -euo pipefail

: "${KIND_VERSION:=v0.26.0}"
: "${KUBECTL_VERSION:=v1.31.4}"

install_bin() {
  local url="$1" dest="$2"
  curl -fsSL "$url" -o "$dest"
  chmod +x "$dest"
}

if ! command -v kind >/dev/null; then
  install_bin "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" /usr/local/bin/kind
fi

if ! command -v kubectl >/dev/null; then
  install_bin "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" /usr/local/bin/kubectl
fi

kind version
kubectl version --client=true
