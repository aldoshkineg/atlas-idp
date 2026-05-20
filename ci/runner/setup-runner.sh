#!/bin/bash
# GitHub Actions Runner Setup Script
# Usage: ./setup-runner.sh <your-github-pat>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <github-personal-access-token>"
    echo ""
    echo "To create a PAT:"
    echo "1. Go to https://github.com/settings/tokens"
    echo "2. Generate new token (classic)"
    echo "3. Select 'repo' scope"
    echo "4. Copy the token and pass it as argument"
    exit 1
fi

GITHUB_TOKEN="$1"
REPO="aldoshkineg/atlas-idp"

echo "Getting runner registration token..."

# Get a registration token for the runner
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO}/actions/runners/registration-token" \
  | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

if [ -z "$REGISTRATION_TOKEN" ]; then
    echo "Failed to get registration token. Check your PAT permissions."
    exit 1
fi

echo "Registration token obtained successfully."
echo ""
echo "To start the runner, run:"
echo ""
echo "  cd $(dirname "$0")"
echo "  RUNNER_TOKEN=${REGISTRATION_TOKEN} docker-compose up -d"
echo ""
echo "Or export the token and run docker-compose:"
echo ""
echo "  export RUNNER_TOKEN=${REGISTRATION_TOKEN}"
echo "  docker-compose up -d"
