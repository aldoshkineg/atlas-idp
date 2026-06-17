#!/bin/bash
# GitHub Actions Runner Setup Script using GitHub CLI
set -o errexit

REPO="aldoshkineg/atlas-idp"
CONTAINER_NAME="github-runner-atlas-idp"

# Check if github-cli is installed
if ! command -v gh >/dev/null 2>&1; then
    echo "Error: github-cli (gh) is not installed."
    echo "Please install it or authenticate via 'gh auth login' first."
    exit 1
fi

# Check if gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh is not authenticated."
    echo "Please run 'gh auth login' before executing this script."
    exit 1
fi

echo "Fetching runner registration token for $REPO via GitHub CLI..."

# Safely fetch the token using gh api and built-in jq expression
REGISTRATION_TOKEN=$(gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/actions/runners/registration-token" \
  --jq '.token')

if [ -z "$REGISTRATION_TOKEN" ]; then
    echo "Failed to obtain registration token. Check your repository permissions."
    exit 1
fi

echo "Registration token obtained successfully."
echo "----------------------------------------"

# Check if docker-compose configuration exists in the current directory
if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
    echo "Error: No docker-compose.yml file found in $(pwd)."
    echo "Please ensure the script is executed from your project directory."
    exit 1
fi

# --- Handle Name Conflicts Automatically ---
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Found an existing container named '$CONTAINER_NAME'. Removing it to avoid conflicts..."
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

echo "Starting the GitHub Actions runner container..."
export RUNNER_TOKEN="${REGISTRATION_TOKEN}"
docker compose up -d

echo "----------------------------------------"
echo "Runner deployment initiated successfully!"
echo "Check status with: docker compose ps"
