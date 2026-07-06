#!/usr/bin/env bash
# incus-control — manage Incus Talos VMs lifecycle
#
# Commands:
#   create [name]   Snapshot all VMs (default: pre-argocd-<timestamp>)
#   restore [name]  Restore all VMs from a snapshot (stop -> restore -> start)
#   list            List snapshots across all VMs
#   delete [name]   Remove a named snapshot from all VMs
#   stop            Hard-stop all running Talos VMs
#   start           Start all Talos VMs and wait for the cluster to settle
#
# Environment:
#   VM_PATTERN      Filter for VM discovery (default: talos-incus-)
#
set -euo pipefail

SNAPSHOT_PREFIX="pre-argocd"
VM_PATTERN="${VM_PATTERN:-talos-incus-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") {create|restore|list|delete|stop|start} [snapshot_name]

Commands:
  create [name]   Snapshot all VMs (default: ${SNAPSHOT_PREFIX}-<timestamp>)
  restore [name]  Restore all VMs from a snapshot (VMs are stopped, restored, then started)
  list            List snapshots for all VMs
  delete [name]   Delete snapshots from all VMs
  stop            Stop all Talos VMs (hard stop)
  start           Start all Talos VMs

Examples:
  $(basename "$0") create
  $(basename "$0") create my-backup
  $(basename "$0") restore pre-argocd-20260706
  $(basename "$0") list
  $(basename "$0") delete pre-argocd-20260706
  $(basename "$0") stop
  $(basename "$0") start
EOF
  exit 1
}

ensure_incus() {
  if ! command -v incus &>/dev/null; then
    echo "ERROR: incus CLI not found"
    exit 1
  fi
}

discover_vms() {
  incus list --format csv 2>/dev/null | \
    grep ",RUNNING," | grep "VIRTUAL-MACHINE" | cut -d, -f1 | \
    grep "^${VM_PATTERN}" | sort || true
}

discover_all_vms() {
  incus list --format csv 2>/dev/null | \
    grep "VIRTUAL-MACHINE" | cut -d, -f1 | \
    grep "^${VM_PATTERN}" | sort || true
}

load_vms() {
  mapfile -t vms < <("$1")
}

snap_name="${2:-${SNAPSHOT_PREFIX}-$(date +%Y%m%d-%H%M%S)}"

create_snapshots() {
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

stop_vms() {
  load_vms discover_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No running Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Stopping ${#vms[@]} VMs..."
  for vm in "${vms[@]}"; do
    echo "  -> Stopping $vm ..."
    incus stop "$vm" --force 2>/dev/null || true
    echo "  -> $vm stopped"
  done
  echo "==> All VMs stopped"
}

start_vms() {
  load_vms discover_all_vms
  if [ ${#vms[@]} -eq 0 ]; then
    echo "No Talos VMs found (pattern: ${VM_PATTERN})"
    return
  fi
  echo "==> Starting ${#vms[@]} VMs..."
  for vm in "${vms[@]}"; do
    echo "  -> Starting $vm ..."
    incus start "$vm"
    echo "  -> $vm started"
  done
  echo "==> All VMs started. Waiting 30s for cluster to settle..."
  sleep 30
  echo "==> Done. Check cluster with: kubectl --kubeconfig /var/tmp/atlas/talos/kubeconfig get nodes"
}

ensure_incus

case "${1:-}" in
  create)  create_snapshots ;;
  restore) restore_snapshots ;;
  list)    list_snapshots ;;
  delete)  delete_snapshots ;;
  stop)    stop_vms ;;
  start)   start_vms ;;
  *)       usage ;;
esac
