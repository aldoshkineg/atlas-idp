FROM catthehacker/ubuntu:act-latest

ENV PIP_BREAK_SYSTEM_PACKAGES=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    python3-pip \
    python3-setuptools \
    xorriso \
    && rm -rf /var/lib/apt/lists/*

COPY install-tools.sh /usr/local/bin/install-tools.sh
COPY install-cmds.sh /tmp/install-cmds.sh

RUN sed -i 's/sudo //g' /usr/local/bin/install-tools.sh

RUN bash /tmp/install-cmds.sh && rm /tmp/install-cmds.sh

RUN mkdir -p /opt/terraform/plugin-cache
