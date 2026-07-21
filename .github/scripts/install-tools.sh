#!/bin/bash

set -eo pipefail

TOOL=$1
VERSION=$2

if command -v "$TOOL" &>/dev/null; then
  echo "$TOOL already installed"
  exit 0
fi

echo "Installing $TOOL"

case $TOOL in

vault)

  curl -fsSL \
    https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_linux_amd64.zip \
    -o vault.zip

  unzip -p vault.zip vault | sudo tee /usr/local/bin/vault > /dev/null
  sudo chmod +x /usr/local/bin/vault
  ;;

terraform)

  curl -fsSL \
    https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip \
    -o terraform.zip

  unzip -o terraform.zip
  sudo mv terraform /usr/local/bin/
  ;;

kubectl)

  curl -LO \
    https://dl.k8s.io/release/v${VERSION}/bin/linux/amd64/kubectl

  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  ;;

kind)

  curl -Lo kind \
    https://kind.sigs.k8s.io/dl/v${VERSION}/kind-linux-amd64

  chmod +x kind
  sudo mv kind /usr/local/bin/
  ;;

trivy)

  curl -sfL \
    https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh |
    sudo sh -s -- -b /usr/local/bin v${VERSION}

  command -v trivy >/dev/null || { echo "trivy install failed"; exit 1; }

  ;;

yamllint)

  if ! command -v yamllint &>/dev/null; then
    pip install yamllint=="$VERSION"
  fi

  ;;

incus)

  curl -fsSL -o incus \
    https://github.com/lxc/incus/releases/download/v${VERSION}/bin.linux.incus.x86_64

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

*)

  echo "Unknown tool"

  exit 1

  ;;

esac
