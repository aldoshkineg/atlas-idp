#!/usr/bin/env bash
#
# atlas-relocate.sh — toggle relocation of Atlas working data and the Incus
# service directory onto the large /mnt/data/box volume via symlinks.
#
# The project hard-codes /var/tmp/atlas in many places (Makefile, *.tf, CI),
# and Incus defaults to /var/lib/incus. Instead of editing all those paths,
# we point them at /mnt/data/box/* with symlinks, so switching is a one-liner.
#
# Usage:
#   sudo ./scripts/atlas-relocate.sh on       # relocate to /mnt/data/box (symlinks)
#   sudo ./scripts/atlas-relocate.sh off      # revert to local paths (box data kept)
#   ./scripts/atlas-relocate.sh status        # show current state
#
# Notes:
#   * "off" recreates empty local dirs; it does NOT delete the relocated data
#     under /mnt/data/box, so "on" can restore the previous state instantly.
#   * Incus is stopped/started around any change to its service directory.
#   * Edit the PAIRS array below to change source/destination locations.
set -euo pipefail

# link_path -> real destination on the big volume
declare -A PAIRS=(
  ["/var/tmp/atlas"]="/mnt/data/box/atlas"
  ["/var/lib/incus"]="/mnt/data/box/incus"
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo) for '$1'"
}

incus_active() { systemctl is-active --quiet incus.service 2>/dev/null; }

incus_stop() {
  if incus_active; then
    log "stopping incus.service + incus.socket"
    systemctl stop incus.service incus.socket 2>/dev/null || true
    STOPPED_INCUS=1
  fi
}

incus_start() {
  if [ "${STOPPED_INCUS:-0}" = "1" ]; then
    log "starting incus.socket + incus.service"
    systemctl start incus.socket 2>/dev/null || true
    systemctl start incus.service 2>/dev/null || true
  fi
}

relocate_on() {
  need_root on
  incus_stop
  for link in "${!PAIRS[@]}"; do
    dest="${PAIRS[$link]}"
    mkdir -p "$dest"
    if [ -L "$link" ]; then
      cur="$(readlink -f "$link")"
      if [ "$cur" = "$(readlink -f "$dest")" ]; then
        log "$link already -> $dest (ok)"
      else
        warn "$link points to $cur; repointing to $dest"
        ln -sfn "$dest" "$link"
      fi
    elif [ -d "$link" ]; then
      log "migrating existing data $link -> $dest"
      rsync -aH --remove-source-files "$link/" "$dest/"
      find "$link" -type d -empty -delete 2>/dev/null || true
      rm -rf "$link"
      ln -sfn "$dest" "$link"
    elif [ ! -e "$link" ]; then
      log "linking $link -> $dest"
      ln -sfn "$dest" "$link"
    else
      die "$link exists and is not a dir/symlink; refusing to touch it"
    fi
  done
  incus_start
  log "relocation ON"
}

relocate_off() {
  need_root off
  incus_stop
  for link in "${!PAIRS[@]}"; do
    dest="${PAIRS[$link]}"
    if [ -L "$link" ]; then
      log "removing symlink $link (data preserved at $dest)"
      rm -f "$link"
      mkdir -p "$link"
    elif [ -d "$link" ]; then
      log "$link is already a local directory (nothing to do)"
    else
      log "creating empty local dir $link"
      mkdir -p "$link"
    fi
  done
  incus_start
  warn "relocation OFF — local dirs are empty; Incus now starts fresh."
  warn "Run 'atlas-relocate.sh on' to restore data from /mnt/data/box."
}

relocate_status() {
  for link in "${!PAIRS[@]}"; do
    dest="${PAIRS[$link]}"
    if [ -L "$link" ]; then
      tgt="$(readlink "$link")"
      if [ "$tgt" = "$dest" ]; then state="RELOCATED -> $tgt"; else state="SYMLINK -> $tgt (unexpected)"; fi
    elif [ -d "$link" ]; then
      state="LOCAL (real dir)"
    elif [ ! -e "$link" ]; then
      state="MISSING"
    else
      state="OTHER"
    fi
    printf '  %-18s %s\n' "$link" "$state"
    if [ -d "$dest" ]; then
      printf '  %-18s dest exists (%s)\n' "" "$(du -sh "$dest" 2>/dev/null | cut -f1) at $dest"
    fi
  done
  printf '  %-18s %s\n' "incus.service" "$(systemctl is-active incus.service 2>/dev/null || echo inactive)"
}

case "${1:-}" in
  on)     relocate_on ;;
  off)    relocate_off ;;
  status) relocate_status ;;
  *) echo "Usage: $0 {on|off|status}" >&2; exit 2 ;;
esac
