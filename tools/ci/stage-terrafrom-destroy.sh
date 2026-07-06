#!/usr/bin/env bash
# stage-terrafrom-destroy.sh — Quick destroy of stage environment.
#
# Cleans up all Incus-managed resources for the Talos-based stage cluster
# and removes the local Terraform state so the next apply starts fresh:
#   - Zot cache container (without cache directory — preserved at /var/tmp/atlas/zot_cache)
#   - Talos control-plane and worker VMs
#   - Storage volumes, storage pool, profile
#   - incusbr0 network bridge
#   - Incus images (Talos, Zot)
#   - Terraform state file
set -euo pipefail

# Note: STAGE_CLUSTER_NAME (not CLUSTER_NAME) to avoid collision with Makefile's CLUSTER_NAME=atlas-idp
STAGE_CLUSTER_NAME="${STAGE_CLUSTER_NAME:-talos-incus}"
TALOS_VERSION="${TALOS_VERSION:-1.11.2}"
IMAGE_ALIAS="talos-${TALOS_VERSION}-drbd"
BRIDGE_NAME="${BRIDGE_NAME:-incusbr0}"
TF_STATE="${TF_STATE:-/var/tmp/atlas/terraform/terraform.tfstate}"

echo "==> Stage Destroy: cleaning resources for cluster '${STAGE_CLUSTER_NAME}'"

# 1. Delete containers
echo "--> Deleting containers..."
if incus info zot-cache &>/dev/null 2>&1; then
  incus delete zot-cache -f
  echo "    deleted container: zot-cache"
else
  echo "    skip (not found): zot-cache"
fi

# 2. Delete VMs
echo "--> Deleting VMs..."
for vm in $(incus list --format csv -c n 2>/dev/null | grep "^${STAGE_CLUSTER_NAME}-" || true); do
  incus delete "$vm" -f
  echo "    deleted VM: $vm"
done
[ -z "$(incus list --format csv -c n 2>/dev/null | grep "^${STAGE_CLUSTER_NAME}-" || true)" ] && echo "    no ${STAGE_CLUSTER_NAME} VMs found"

# 3. Delete storage volumes
echo "--> Deleting storage volumes..."
if incus storage info extra-pool &>/dev/null 2>&1; then
  for vol in $(incus storage volume list extra-pool --format csv 2>/dev/null | cut -d, -f2); do
    incus storage volume delete extra-pool "$vol" 2>/dev/null && echo "    deleted volume: $vol" || true
  done
fi

# 4. Delete storage pool
echo "--> Deleting storage pool..."
if incus storage info extra-pool &>/dev/null 2>&1; then
  incus storage delete extra-pool
  echo "    deleted storage pool: extra-pool"
else
  echo "    skip (not found): extra-pool"
fi

# 5. Delete profile
echo "--> Deleting profile..."
if incus profile show talos-vm &>/dev/null 2>&1; then
  incus profile delete talos-vm
  echo "    deleted profile: talos-vm"
else
  echo "    skip (not found): talos-vm"
fi

# 6. Delete Talos image (Zot image preserved — null_resource skips copy if present)
echo "--> Deleting images..."
if incus image show "$IMAGE_ALIAS" &>/dev/null 2>&1; then
  incus image delete "$IMAGE_ALIAS"
  echo "    deleted image: $IMAGE_ALIAS"
else
  echo "    skip (not found): $IMAGE_ALIAS"
fi

# 7. Delete bridge
echo "--> Deleting bridge..."
if incus network show "$BRIDGE_NAME" &>/dev/null 2>&1; then
  incus network delete "$BRIDGE_NAME"
  echo "    deleted bridge: $BRIDGE_NAME"
else
  echo "    skip (not found): $BRIDGE_NAME"
fi

# 8. Clean up Terraform state
echo "--> Cleaning up Terraform state..."
if [ -f "$TF_STATE" ]; then
  sudo rm -f "$TF_STATE"
  echo "    deleted: $TF_STATE"
else
  echo "    skip (not found)"
fi
