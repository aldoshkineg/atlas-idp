#!/bin/bash
set -e

RUNNER_DIR="/home/runner"
CONFIG_SH="${RUNNER_DIR}/config.sh"
RUN_SH="${RUNNER_DIR}/run.sh"

# Check required environment variables
if [ -z "$RUNNER_TOKEN" ]; then
    echo "Error: RUNNER_TOKEN is required"
    exit 1
fi

if [ -z "$REPO_URL" ] && [ -z "$ORG_URL" ] && [ -z "$ENTERPRISE_URL" ]; then
    echo "Error: REPO_URL, ORG_URL, or ENTERPRISE_URL is required"
    exit 1
fi

cd "${RUNNER_DIR}"

# Check if runner is already configured
if [ ! -f ".runner" ]; then
    echo "Configuring runner..."
    
    CONFIG_ARGS="--url ${REPO_URL} --token ${RUNNER_TOKEN} --name ${RUNNER_NAME:-github-runner} --work ${RUNNER_WORKDIR:-/tmp/runner/work} --labels ${LABELS:-self-hosted}"
    
    if [ "${RUNNER_SCOPE}" = "org" ]; then
        CONFIG_ARGS="${CONFIG_ARGS} --runnergroup ${RUNNER_GROUP:-Default}"
    fi
    
    if [ "${EPHEMERAL:-false}" = "true" ]; then
        CONFIG_ARGS="${CONFIG_ARGS} --ephemeral"
    fi
    
    if [ "${DISABLE_UPDATE:-false}" = "true" ]; then
        CONFIG_ARGS="${CONFIG_ARGS} --disableupdate"
    fi
    
    echo "Running: ${CONFIG_SH} ${CONFIG_ARGS}"
    ${CONFIG_SH} ${CONFIG_ARGS}
else
    echo "Runner already configured."
fi

echo "Starting runner..."
exec ${RUN_SH} "$@"
