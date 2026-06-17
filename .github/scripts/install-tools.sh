#!/bin/bash

set -e

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

  ;;

yamllint)

  if ! command -v yamllint &>/dev/null; then
    pip install yamllint=="$VERSION"
  fi

  ;;

*)

  echo "Unknown tool"

  exit 1

  ;;

esac
