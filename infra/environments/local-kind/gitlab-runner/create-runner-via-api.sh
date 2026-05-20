#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

: "${GITLAB_URL:=https://gitlab.com}"
: "${GITLAB_PROJECT_PATH:=aldoshkineg/atlas-idp}"
: "${RUNNER_NAME:=atlas-idp-local}"
: "${RUNNER_TAGS:=atlas-idp,kind,local,docker}"

if [[ -z "${GITLAB_PAT:-}" ]]; then
  echo "ERROR: Set GITLAB_PAT in infra/environments/local-kind/gitlab-runner/.env"
  exit 1
fi

API="${GITLAB_URL}/api/v4"
PROJECT_ENC="${GITLAB_PROJECT_PATH//\//%2F}"

PROJECT_JSON="$(curl -fsS --header "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "${API}/projects/${PROJECT_ENC}")"

PROJECT_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "${PROJECT_JSON}")"

RESP="$(curl -fsS --request POST --header "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "${API}/projects/${PROJECT_ID}/runners" \
  --form "runner_type=project_type" \
  --form "description=${RUNNER_NAME}" \
  --form "tag_list=${RUNNER_TAGS}" \
  --form "run_untagged=true" \
  --form "locked=false" \
  --form "access_level=not_protected")"

TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<< "${RESP}")"

umask 077
cat > .env <<EOF
GITLAB_PAT=${GITLAB_PAT}
GITLAB_RUNNER_TOKEN=${TOKEN}
GITLAB_URL=https://gitlab.com/
GITLAB_PROJECT_PATH=${GITLAB_PROJECT_PATH}
RUNNER_NAME=${RUNNER_NAME}
EOF

chmod 600 .env
echo "Runner created. Token saved to gitlab-runner/.env (gitignored)"
echo "Next: make runner-register"
