#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQ_FILE="$REPO_ROOT/REQUIREMENTS.md"

FAIL=0
WARN=0

ok()   { printf '  [OK]      %s\n' "$1"; }
info() { printf '  [INFO]    %s\n' "$1"; }
warn() { printf '  [WARN]    %s\n' "$1"; WARN=$((WARN + 1)); }
fail() { printf '  [FAIL]    %s\n' "$1"; FAIL=$((FAIL + 1)); }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

bin_version() {
  local b="$1" v=""
  for flag in --version version -v -V; do
    if v="$("$b" $flag 2>/dev/null | head -1)" && [ -n "$v" ] && [ "${v#Error}" = "$v" ]; then
      break
    else
      v=""
    fi
  done
  printf '%s' "$v"
}

echo "==> Binaries (from $REQ_FILE: Local CLI Tooling)"
if [ ! -f "$REQ_FILE" ]; then
  warn "REQUIREMENTS.md not found -- skipping binary checks"
else
  while IFS='|' read -r _ tool ver _; do
    tool="$(trim "$tool")"; ver="$(trim "$ver")"
    [ -z "$tool" ] && continue
    [ "$tool" = "Tool" ] && continue
    [ "${tool//-/}" = "" ] && continue
    case "$tool" in
      "docker compose") bin="docker"; cmd="docker compose version" ;;
      "docker buildx")  bin="docker"; cmd="docker buildx version" ;;
      *) bin="$tool"; cmd="" ;;
    esac
    if [ -n "$cmd" ]; then
      if $cmd >/dev/null 2>&1; then
        ok "$tool available (required $ver)"
      else
        fail "$tool not available -- need docker with the $tool plugin (required $ver)"
      fi
    elif command -v "$bin" >/dev/null 2>&1; then
      ok "binary: $tool ($(bin_version "$bin") | required $ver)"
    else
      fail "binary missing: $tool (required $ver)"
    fi
  done < <(awk '/^## Local CLI Tooling/{f=1;next} /^## /{if(f)exit} f' "$REQ_FILE" | grep '^|')
fi

echo "==> Images"
if docker image inspect act-runner:latest >/dev/null 2>&1; then
  ok "docker image: act-runner:latest"
else
  fail "docker image missing: act-runner:latest (run 'make act-build')"
fi

if incus image list -f csv 2>/dev/null | cut -d, -f1 | grep -qx zot-cache; then
  ok "incus image alias: zot-cache"
else
  fail "incus image alias missing: zot-cache (run 'make zot-image')"
fi

echo "==> Paths"
if [ -d /var/tmp ] && [ -w /var/tmp ]; then
  ok "writable: /var/tmp"
else
  fail "not writable: /var/tmp"
fi

if [ -d /var/tmp/atlas ]; then
  ok "path exists: /var/tmp/atlas"
else
  warn "path missing: /var/tmp/atlas (auto-created by act-runner on first run)"
fi

if [ -S /var/lib/incus/unix.socket ]; then
  ok "incus socket present: /var/lib/incus/unix.socket"
else
  fail "incus socket missing: /var/lib/incus/unix.socket"
fi



echo "==> Config"
if [ -f "$REPO_ROOT/.env" ]; then
  ok ".env present"
  set +u
  . "$REPO_ROOT/.env"
  set -u
  for k in ATLAS_CA_CRT_B64 ATLAS_CA_KEY_B64; do
    if [ -n "${!k:-}" ]; then
      ok "env (required): $k"
    else
      fail "env empty (required): $k  -- this is the CA materialised into security/certs by ci-base"
    fi
  done
  for k in VAULT_TOKEN VL_MINIO_ROOT_USER VL_MINIO_ROOT_PASSWORD VL_REDIS_PASSWORD VL_GRAFANA_PASSWORD COSIGN_PRIVATE_KEY_B64; do
    if [ -n "${!k:-}" ]; then
      ok "env: $k"
    else
      warn "env empty: $k (Vault seeds / cosign key may be needed by later stages)"
    fi
  done
else
  fail ".env missing (copy .env.example to .env and fill in)"
fi

if [ -f "$REPO_ROOT/.secrets" ]; then
  set +u
  . "$REPO_ROOT/.secrets"
  set -u
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    ok ".secrets: GITHUB_TOKEN present"
  else
    warn ".secrets: GITHUB_TOKEN empty (act rate-limit / gh CLI may fail)"
  fi
else
  warn ".secrets missing (needed for GITHUB_TOKEN in act)"
fi

echo "==> Runtime daemons"
if docker info >/dev/null 2>&1; then
  ok "docker daemon reachable"
else
  fail "docker daemon not reachable"
fi

if incus info >/dev/null 2>&1; then
  ok "incus daemon reachable"
else
  fail "incus daemon not reachable"
fi

echo "==> Network"
if command -v ip >/dev/null 2>&1; then
  if ip -o -4 addr show 2>/dev/null | awk '{print $4}' | grep -q '^10\.200\.10\.'; then
    if [ -f /var/tmp/atlas/talos/kubeconfig ]; then
      info "local interface uses 10.200.10.0/24 -- expected, a cluster is already bootstrapped here"
    else
      warn "a local interface already uses 10.200.10.0/24 (Talos control-plane / LB pool) -- possible clash for a fresh bootstrap"
    fi
  else
    ok "no clash with 10.200.10.0/24"
  fi
else
  warn "iproute2 (ip) not found -- skipped CIDR clash check"
fi

if command -v curl >/dev/null 2>&1; then
  if curl -sS -o /dev/null --max-time 5 https://ghcr.io/v2/ 2>/dev/null; then
    ok "ghcr.io reachable"
  else
    warn "ghcr.io not reachable (seal image pull may fail)"
  fi
else
  warn "curl not found -- skipped ghcr.io reachability check"
fi

echo "==> Resources"
if [ -r /proc/meminfo ]; then
  mem_gb=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 / 1024 ))
  if [ "$mem_gb" -lt 8 ]; then
    fail "available memory ${mem_gb}GB < 8GB minimum to run the project"
  elif [ "$mem_gb" -lt 12 ]; then
    ok "memory: ${mem_gb}GB (runs, but < 12GB recommended for the base layer)"
  elif [ "$mem_gb" -lt 32 ]; then
    ok "memory: ${mem_gb}GB (base layer OK; full all-layers run recommended 32GB)"
  else
    ok "memory: ${mem_gb}GB (base + full all-layers capable)"
  fi
else
  warn "/proc/meminfo not readable -- skipped memory check"
fi

echo "==> Cluster state (informational)"
if [ -f /var/tmp/atlas/talos/kubeconfig ]; then
  info "kubeconfig present at /var/tmp/atlas/talos/kubeconfig (a cluster may already be bootstrapped)"
else
  info "no kubeconfig yet at /var/tmp/atlas/talos/kubeconfig (fresh bootstrap expected)"
fi

echo ""
echo "Preflight summary: ${FAIL} failure(s), ${WARN} warning(s)"
[ "$FAIL" -eq 0 ]
