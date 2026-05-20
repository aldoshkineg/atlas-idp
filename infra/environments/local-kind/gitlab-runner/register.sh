#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

: "${GITLAB_URL:=https://gitlab.com/}"
: "${RUNNER_NAME:=atlas-idp-local}"
: "${RUNNER_TAGS:=atlas-idp,kind,local,docker}"

mkdir -p config

if [[ -f config/config.toml ]] && grep -q '^\[\[runners\]\]' config/config.toml 2>/dev/null; then
  echo "Runner already registered — applying kind configuration"
  "${DIR}/configure-runner.sh"
  docker compose up -d --force-recreate
  exit 0
fi

if [[ -z "${GITLAB_RUNNER_TOKEN:-}" || "${GITLAB_RUNNER_TOKEN}" == glrt-REPLACE_ME ]]; then
  echo "ERROR: Set GITLAB_RUNNER_TOKEN in infra/environments/local-kind/gitlab-runner/.env"
  echo "  cp .env.example .env"
  echo ""
  echo "Create runner in GitLab UI (tags only in UI):"
  echo "  Settings → CI/CD → Runners → New project runner"
  echo "  Tags: ${RUNNER_TAGS}"
  exit 1
fi

# glrt-*: only name + executor on register
docker compose run --rm gitlab-runner register \
  --non-interactive \
  --url "${GITLAB_URL}" \
  --token "${GITLAB_RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --executor docker \
  --docker-image docker:27-cli \
  --docker-privileged \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-volumes "/cache"

if [[ -f config/config.toml ]]; then
  chown "$(id -u):$(id -g)" config/config.toml 2>/dev/null || sudo chown "$(id -u):$(id -g)" config/config.toml
  chmod 600 config/config.toml
fi

"${DIR}/configure-runner.sh"
docker compose up -d --force-recreate
echo "Runner registered (config in gitlab-runner/config/, gitignored)"
