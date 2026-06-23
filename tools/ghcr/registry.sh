#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  export "$(grep GITHUB_TOKEN "$ENV_FILE" | head -1)"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: GITHUB_TOKEN not found in $ENV_FILE or environment" >&2
  exit 1
fi

TOKEN="$GITHUB_TOKEN"
API_ROOT="https://api.github.com"
OWNER="aldoshkineg"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  list <package>          List all versions (tags) for a package
  delete <package> <tag>  Delete a specific version by tag
  pull <package> <tag>    Pull image from GHCR to local Docker

Examples:
  $(basename "$0") list seal-api
  $(basename "$0") delete seal-worker 0.2.0-alpha
  $(basename "$0") pull seal-ui 0.2.0-alpha
EOF
  exit 1
}

list_versions() {
  local pkg="$1"
  curl -sf -H "Authorization: token $TOKEN" \
    "$API_ROOT/user/packages/container/$pkg/versions" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for v in data:
    tags = v['metadata']['container']['tags']
    if tags:
        print(f\"  {v['id']:>10}  {', '.join(tags)}\")
" 2>/dev/null || echo "  (no versions or package not found)"
}

delete_tag() {
  local pkg="$1"
  local tag="$2"
  versions=$(curl -sf -H "Authorization: token $TOKEN" \
    "$API_ROOT/user/packages/container/$pkg/versions" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for v in data:
    if '$tag' in v['metadata']['container']['tags']:
        print(v['id'])
" 2>/dev/null)
  if [ -z "$versions" ]; then
    echo "Error: tag '$tag' not found in $pkg" >&2
    exit 1
  fi
  for vid in $versions; do
    echo "Deleting $pkg version $vid (tag: $tag)..."
    curl -sf -X DELETE -H "Authorization: token $TOKEN" \
      "$API_ROOT/user/packages/container/$pkg/versions/$vid" > /dev/null && \
      echo "  done" || echo "  failed"
  done
}

pull_image() {
  local pkg="$1"
  local tag="$2"
  local image="ghcr.io/$OWNER/$pkg:$tag"
  echo "Pulling $image ..."
  echo "$TOKEN" | docker login ghcr.io -u "$OWNER" --password-stdin > /dev/null 2>&1
  docker pull "$image"
  docker logout ghcr.io > /dev/null 2>&1
}

[ $# -lt 2 ] && usage

cmd="$1"
pkg="$2"
tag="${3:-}"

case "$cmd" in
  list) list_versions "$pkg" ;;
  delete) [ -z "$tag" ] && usage; delete_tag "$pkg" "$tag" ;;
  pull) [ -z "$tag" ] && usage; pull_image "$pkg" "$tag" ;;
  *) usage ;;
esac
