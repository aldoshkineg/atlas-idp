#!/usr/bin/env bash
# incus-control — manage Incus Talos VMs lifecycle
#
# Commands:
#   create [name]     Snapshot all running VMs (default: pre-argocd-<timestamp>)
#   restore <name>    Restore all VMs from a snapshot (stop -> restore -> start)
#   list              List snapshots across all VMs
#   delete <name>     Remove a named snapshot from all VMs
#   stop [target]     Hard-stop VMs (target: "all" or a VM name; default: all)
#   start [target]    Start VMs (target: "all" or a VM name; default: all)
#
# Environment:
#   VM_PATTERN        Filter for VM discovery (default: talos-incus-)
#
set -euo pipefail

SNAPSHOT_PREFIX="pre-argocd"
VM_PATTERN="${VM_PATTERN:-talos-incus-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") {create|restore|list|delete|stop|start} [arg]

Commands:
  create [name]     Snapshot all running VMs (default: ${SNAPSHOT_PREFIX}-<timestamp>)
  restore <name>    Restore all VMs from a snapshot (VMs are stopped, restored, then started)
  list              List snapshots for all VMs
  delete <name>     Delete a named snapshot from all VMs
  stop [target]     Hard-stop VMs — target is "all" or a single VM name (default: all)
  start [target]    Start VMs — target is "all" or a single VM name (default: all)

Examples:
  $(basename "$0") create
  $(basename "$0") create my-backup
  $(basename "$0") restore pre-argocd-20260706
  $(basename "$0") list
  $(basename "$0") delete pre-argocd-20260706
  $(basename "$0") stop all
  $(basename "$0") stop talos-incus-cp-1
  $(basename "$0") start talos-incus-worker-1
EOF
  exit 1
}

ensure_incus() {
  if ! command -v incus &>/dev/null; then
    echo "ERROR: incus CLI not found"
    exit 1
  fi
}

list_raw() {
  # name,status,type — quoting stripped so multi-IP VMs parse cleanly
  incus list -c n,s,t --format csv 2>/dev/null | tr -d '"' || true
}

discover_vms() {
  list_raw | awk -F, -v pat="^${VM_PATTERN}" \
    '$2=="RUNNING" && $3=="VIRTUAL-MACHINE" && $1 ~ pat {print $1}' | sort || true
}

discover_all_vms() {
  list_raw | awk -F, -v pat="^${VM_PATTERN}" \
    '$3=="VIRTUAL-MACHINE" && $1 ~ pat {print $1}' | sort || true
}

vm_exists() {
  list_raw | awk -F, -v name="$1" '$1==name {found=1} END{exit !found}'
}

load_vms() {
  mapfile -t vms < <("$1")
}

create_snapshots() {
  local snap_name="${1:-${SNAPSHOT_PREFIX}-$(date +%Y%m%d-%H%M%S)}"
  load_vms discover_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "ERROR: No running Talos VMs found (pattern: ${VM_PATTERN})"
    exit 1
  fi
  echo "==> Creating snapshot '$snap_name' on ${#vms[@]} VMs..."
  for vm in "${vms[@]}"; do
    echo "  -> Snapshotting $vm ..."
    incus snapshot create "$vm" "$snap_name"
    echo "  -> $vm snapshot created"
  done
  echo "==> All snapshots created successfully"
}

restore_snapshots() {
  local snap_name="${1:-}"
  if [ -z "$snap_name" ]; then
    echo "ERROR: restore requires a snapshot name"
    echo "Usage: $(basename "$0") restore <snapshot_name>"
    exit 1
  fi
  load_vms discover_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "ERROR: No running Talos VMs found (pattern: ${VM_PATTERN})"
    exit 1
  fi
  echo "==> Restoring snapshot '$snap_name' on ${#vms[@]} VMs..."
  for vm in "${vms[@]}"; do
    mapfile -t snapshots < <(incus snapshot list "$vm" --format csv 2>/dev/null | cut -d, -f1 || true)
    if ! printf '%s\n' "${snapshots[@]}" | grep -qx "$snap_name"; then
      echo "ERROR: Snapshot '$snap_name' not found on $vm"
      exit 1
    fi
    echo "  -> Stopping $vm ..."
    incus stop "$vm" --force 2>/dev/null || true
    echo "  -> Restoring $vm from snapshot '$snap_name' ..."
    incus snapshot restore "$vm" "$snap_name"
    echo "  -> Starting $vm ..."
    incus start "$vm"
    echo "  -> $vm restored"
  done
  echo "==> All VMs restored. Waiting 30s for cluster to settle..."
  sleep 30
  echo "==> Done. Check cluster with: kubectl --kubeconfig /var/tmp/atlas/talos/kubeconfig get nodes"
}

list_snapshots() {
  load_vms discover_all_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Snapshots:"
  for vm in "${vms[@]}"; do
    echo "  $vm:"
    while IFS=, read -r name _created _state; do
      echo "    - $name ($_created, $_state)"
    done < <(incus snapshot list "$vm" --format csv 2>/dev/null || true)
  done
}

delete_snapshots() {
  local snap_name="${1:-}"
  if [ -z "$snap_name" ]; then
    echo "ERROR: delete requires a snapshot name"
    echo "Usage: $(basename "$0") delete <snapshot_name>"
    exit 1
  fi
  load_vms discover_all_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Deleting snapshot '$snap_name' from ${#vms[@]} VMs..."
  for vm in "${vms[@]}"; do
    mapfile -t snapshots < <(incus snapshot list "$vm" --format csv 2>/dev/null | cut -d, -f1 || true)
    if printf '%s\n' "${snapshots[@]}" | grep -qx "$snap_name"; then
      echo "  -> Deleting $snap_name from $vm ..."
      incus snapshot delete "$vm" "$snap_name"
    else
      echo "  -> Snapshot '$snap_name' not found on $vm, skipping"
    fi
  done
  echo "==> Done"
}

resolve_target_vms() {
  local target="${1:-all}"
  vms=()
  if [ "$target" = "all" ]; then
    load_vms discover_vms
  else
    if ! vm_exists "$target"; then
      echo "ERROR: VM '$target' not found"
      exit 1
    fi
    vms=("$target")
  fi
}

stop_vms() {
  local target="${1:-all}"
  resolve_target_vms "$target"
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No running Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Stopping ${#vms[@]} VM(s) (target: $target)..."
  for vm in "${vms[@]}"; do
    echo "  -> Stopping $vm ..."
    incus stop "$vm" --force 2>/dev/null || true
    echo "  -> $vm stopped"
  done
  echo "==> Targeted VMs stopped"
}

start_vms() {
  local target="${1:-all}"
  local -a vms=()
  if [ "$target" = "all" ]; then
    load_vms discover_all_vms
    vms=("${vms[@]}")
  else
    if ! vm_exists "$target"; then
      echo "ERROR: VM '$target' not found"
      exit 1
    fi
    vms=("$target")
  fi
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Starting ${#vms[@]} VM(s) (target: $target)..."
  for vm in "${vms[@]}"; do
    echo "  -> Starting $vm ..."
    incus start "$vm"
    echo "  -> $vm started"
  done
  echo "==> Targeted VMs started. Waiting 30s for cluster to settle..."
  sleep 30
  echo "==> Done. Check cluster with: kubectl --kubeconfig /var/tmp/atlas/talos/kubeconfig get nodes"
}

ensure_incus

case "${1:-}" in
  create)  create_snapshots "${2:-}" ;;
  restore) restore_snapshots "${2:-}" ;;
  list)    list_snapshots ;;
  delete)  delete_snapshots "${2:-}" ;;
  stop)    stop_vms "${2:-all}" ;;
  start)   start_vms "${2:-all}" ;;
  *)       usage ;;
esac
