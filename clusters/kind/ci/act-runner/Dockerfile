FROM catthehacker/ubuntu:act-latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    python3-pip \
    python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

ARG TERRAFORM_VERSION=1.15.3
ARG KUBECTL_VERSION=1.34.0
ARG KIND_VERSION=0.29.0
ARG TRIVY_VERSION=0.70.0
ARG YAMLLINT_VERSION=1.35.1

RUN curl -fsSL \
    https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip

RUN curl -LO https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

RUN curl -Lo /usr/local/bin/kind \
    https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind

RUN curl -sfL \
    https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin v${TRIVY_VERSION}

RUN pip install yamllint=="${YAMLLINT_VERSION}" --break-system-packages

RUN mkdir -p /opt/terraform/plugin-cache