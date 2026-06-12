#!/bin/sh
# Install Local Container Image Cache (Zot Registry Proxy)
set -o errexit

# 0. Configuration & Parsing
reg_name='kind-zot-registry'
reg_port='5000'
kind_network='kind'
config_file="zot-config.json"
cache_dir="zot-cache-data" # Папка на хосте для хранения кэшированных образов
purge_requested=false

# Parse command line arguments
for arg in "$@"; do
  case $arg in
    -p|--purge)
      purge_requested=true
      shift
      ;;
  esac
done

# --- Handle Purge Feature ---
if [ "$purge_requested" = true ]; then
  if docker inspect "$reg_name" >/dev/null 2>&1; then
    echo "Purging Zot registry container: $reg_name..."
    docker rm -f "$reg_name" >/dev/null
    echo "Zot container removed successfully."
  else
    echo "No Zot container found to purge."
  fi
  echo "Note: The local cache directory '$cache_dir' and '$kind_network' network were kept intact."
  exit 0
fi

# Check 1: Verify the configuration file exists in the current directory.
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file $config_file not found in the current directory!"
  echo "Please ensure you run this script from the directory containing $config_file."
  exit 1
fi

# Check 2: Ensure the local cache directory exists
if [ ! -d "$cache_dir" ]; then
  echo "Creating local cache directory: $cache_dir"
  mkdir -p "$cache_dir"
fi

# Check 3: Ensure the 'kind' docker network exists.
if ! docker network inspect "$kind_network" >/dev/null 2>&1; then
  echo "Creating docker network: $kind_network"
  docker network create "$kind_network"
fi

# --- 1. Start, Recreate, or Restart Zot registry ---
if docker inspect "$reg_name" >/dev/null 2>&1; then
  # Проверяем, что примонтированы И конфиг, И папка с кэшем
  current_config=$(docker inspect "$reg_name" --format='{{.HostConfig.Binds}}' | grep "$config_file" || true)
  current_cache=$(docker inspect "$reg_name" --format='{{.HostConfig.Binds}}' | grep "$cache_dir" || true)

  if [ -z "$current_config" ] || [ -z "$current_cache" ]; then
    echo "Found an old Zot container without the correct configuration or cache mounts. Recreating..."
    docker rm -f "$reg_name" >/dev/null 2>&1
  else
    # Container exists and has the right settings -> Restart it to pick up changes
    echo "Zot container exists with correct settings. Restarting to apply any config updates..."
    docker restart "$reg_name" >/dev/null

    # Ensure the container is connected to the 'kind' network
    docker network connect "$kind_network" "$reg_name" 2>/dev/null || true

    echo "\nZot restart complete!"
    echo "Registry is accessible locally at: http://localhost:$reg_port"
    exit 0
  fi
fi

# Start Zot from scratch if it doesn't exist (or was just removed due to bad config)
echo "Starting Zot registry container: $reg_name"
docker run -d \
  --restart=always \
  --name "$reg_name" \
  --network "$kind_network" \
  -p "127.0.0.1:$reg_port:5000" \
  --ulimit nofile=65535:65535 \
  -v "$(pwd)/$config_file:/etc/zot/config.json:ro" \
  -v "$(pwd)/$cache_dir:/var/lib/registry:rw" \
  ghcr.io/project-zot/zot:latest

echo "\nZot setup complete!"
echo "Registry is accessible locally at: http://localhost:$reg_port"
echo "Check cache status: curl -s http://localhost:$reg_port/v2/_catalog"
