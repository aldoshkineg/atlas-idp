#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${DIR}/config/config.toml"

if [[ ! -f "${CONFIG}" ]]; then
  echo "No ${CONFIG} — run register.sh first"
  exit 1
fi

export CONFIG
python3 <<'PY'
import os
from pathlib import Path

config_path = Path(os.environ["CONFIG"])
text = config_path.read_text()

if "privileged = true" in text and "docker.sock" in text:
    print("config.toml already configured for kind")
else:
    docker_block = """
  [runners.docker]
    privileged = true
    pull_policy = ["if-not-present"]
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
"""
    if "[runners.docker]" not in text:
        text = text.rstrip() + "\n" + docker_block + "\n"
    else:
        if "privileged = true" not in text:
            text = text.replace(
                "[runners.docker]",
                '[runners.docker]\n    privileged = true\n    pull_policy = ["if-not-present"]\n    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]',
                1,
            )
    config_path.write_text(text)
    config_path.chmod(0o600)
    print("Updated config.toml for kind")
PY
