#!/bin/sh
# Install Local Container Image Cache (Zot Registry Proxy)
set -o errexit

# 0. Configuration
reg_name='kind-zot-registry'
reg_port='5000'
kind_network='kind'
config_file="zot-config.json"

# Check 1: Verify the configuration file exists in the current directory.
# If missing, docker run would create an empty directory on the host, breaking Zot.
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file $config_file not found in the current directory!"
  echo "Please ensure you run this script from the directory containing $config_file."
  exit 1
fi

# Check 2: Ensure the 'kind' docker network exists.
# This allows Zot and future KinD nodes to communicate using container names.
if ! docker network inspect "$kind_network" >/dev/null 2>&1; then
  echo "Creating docker network: $kind_network"
  docker network create "$kind_network"
fi

# --- 1. Start or recreate Zot registry ---
# If the container exists but is misconfigured (e.g., missing the config mount), remove it.
if docker inspect "$reg_name" >/dev/null 2>&1; then
  current_config=$(docker inspect "$reg_name" --format='{{.HostConfig.Binds}}' | grep "$config_file" || true)
  if [ -z "$current_config" ]; then
    echo "Found an old Zot container without the correct configuration. Recreating..."
    docker rm -f "$reg_name" >/dev/null 2>&1
  fi
fi

# Start Zot if it is not already running
if [ "$(docker inspect -f '{{.State.Running}}' "$reg_name" 2>/dev/null || true)" != 'true' ]; then
  echo "Starting Zot registry container: $reg_name"
  docker run -d \
    --restart=always \
    --name "$reg_name" \
    --network "$kind_network" \
    -p "127.0.0.1:$reg_port:5000" \
    -v "$(pwd)/$config_file:/etc/zot/config.json:ro" \
    ghcr.io/project-zot/zot:latest
else
  echo "Zot registry container ($reg_name) is already running."
  # Ensure the container is connected to the 'kind' network if it was disconnected
  docker network connect "$kind_network" "$reg_name" 2>/dev/null || true
fi

echo "\nZot setup complete!"
echo "Registry is accessible locally at: http://localhost:$reg_port"
echo "Check cache status: curl -s http://localhost:$reg_port/v2/_catalog"
