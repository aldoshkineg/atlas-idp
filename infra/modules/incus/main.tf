# 1. Managed Incus bridge (NAT, no DHCP)
resource "incus_network" "talos_bridge" {
  name    = var.bridge_name
  project = var.project
  type    = "bridge"
  config = {
    "ipv4.address" = var.bridge_subnet
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}

# 2. VM profile (root disk + bridged NIC)
resource "incus_profile" "talos_vm" {
  name    = "talos-vm"
  project = var.project

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = var.disk_size
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = incus_network.talos_bridge.name
    }
  }

  depends_on = [incus_network.talos_bridge]
}

# Timestamp for metadata — derived from qcow2 mtime, not current time
locals {
  image_dir = abspath(dirname(var.talos_image_file))
}

# 3. Download Talos qcow2 image (only if missing)
resource "null_resource" "download_image" {
  triggers = {
    image_path = var.talos_image_file
    image_url  = var.talos_image_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f '${var.talos_image_file}' ]; then
        echo "=== Downloading from ${var.talos_image_url} ==="
        mkdir -p "$(dirname '${var.talos_image_file}')"
        curl -L -o '${var.talos_image_file}' '${var.talos_image_url}'
      fi
    EOT
  }
}

# 4. Metadata tarball for VM image import (stable across applies)
resource "null_resource" "metadata_yaml" {
  triggers = {
    image_path = var.talos_image_file
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      FILE='${var.talos_image_file}'
      DIR='${local.image_dir}'
      if [ ! -f "$DIR/metadata.tar.gz" ]; then
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo 0)
        cat <<EOF > "$DIR/metadata.yaml"
architecture: "x86_64"
creation_date: $MTIME
properties:
  description: "Talos OS Cloud-Native Image"
  os: "talos"
  type: "virtual-machine"
EOF
        tar -czf "$DIR/metadata.tar.gz" -C "$DIR" metadata.yaml
      fi
    EOT
  }

  depends_on = [null_resource.download_image]
}

# 5. Import image into Incus (native resource)
resource "incus_image" "talos" {
  project = var.project
  source_file = {
    data_path     = var.talos_image_file
    metadata_path = "${local.image_dir}/metadata.tar.gz"
  }
  alias {
    name = var.image_alias
  }

  depends_on = [null_resource.download_image, null_resource.metadata_yaml]
}

# 6. Image data source (resolves fingerprint)
data "incus_image" "talos" {
  depends_on = [incus_image.talos]
  name       = var.image_alias
  project    = var.project
}

# 7. VM name derivation
locals {
  cp_names = [for i in range(nonsensitive(length(var.controlplane_configs))) : "${var.cluster_name}-cp-${i + 1}"]
  wk_count = nonsensitive(length(var.worker_configs))
  wk_names = [for i in range(local.wk_count) : "${var.cluster_name}-worker-${i + 1}"]

  vm_configs = merge(
    { for i, name in local.cp_names : name => var.controlplane_configs[i] },
    { for i, name in local.wk_names : name => var.worker_configs[i] },
  )
}

# 8. Seed ISO user-data / meta-data files
resource "local_sensitive_file" "user_data" {
  for_each = local.vm_configs

  content  = each.value
  filename = "${var.seed_iso_dir}/${each.key}/user-data"
}

resource "local_file" "meta_data" {
  for_each = local.vm_configs

  content  = "instance-id: ${each.key}\nlocal-hostname: ${each.key}"
  filename = "${var.seed_iso_dir}/${each.key}/meta-data"
}

# 9. Seed ISO assembly
resource "null_resource" "seed_iso" {
  for_each = local.vm_configs

  depends_on = [
    local_sensitive_file.user_data,
    local_file.meta_data,
  ]

  triggers = {
    user_data_sha256 = sha256(each.value)
    meta_data_sha256 = sha256(local_file.meta_data[each.key].content)
  }

  provisioner "local-exec" {
    command = "xorriso -as mkisofs -r -V cidata -J -o '${var.seed_iso_dir}/${each.key}.iso' '${var.seed_iso_dir}/${each.key}/'"
  }
}

# 10. Controlplane VMs
resource "incus_instance" "controlplane" {
  for_each = toset(local.cp_names)

  project  = var.project
  name     = each.key
  image    = data.incus_image.talos.fingerprint
  type     = "virtual-machine"
  profiles = [incus_profile.talos_vm.name]
  running  = true

  config = {
    "security.secureboot" = "false"
    "limits.cpu"          = var.cpu
    "limits.memory"       = var.cp_memory
    "raw.qemu"            = "-drive file=${var.seed_iso_dir}/${each.key}.iso,if=ide,media=cdrom,format=raw,readonly=on"
  }

  depends_on = [
    null_resource.seed_iso,
    incus_profile.talos_vm,
    incus_network.talos_bridge,
  ]
}

# 11. LVM storage pool for block volumes (used by worker extra disks)
resource "incus_storage_pool" "extra" {
  count  = var.extra_disk_size != "" ? 1 : 0
  name   = "extra-pool"
  driver = "lvm"

  config = {
    size               = var.extra_pool_size
    "lvm.vg_name"      = "incus-extra"
    "lvm.use_thinpool" = "false"
  }
}

# 12. Worker extra storage volumes (for LINSTOR)
resource "incus_storage_volume" "worker_extra" {
  count = var.extra_disk_size != "" ? length(local.wk_names) : 0

  name         = "${local.wk_names[count.index]}-data"
  pool         = incus_storage_pool.extra[0].name
  content_type = "block"

  config = {
    size = var.extra_disk_size
  }

  depends_on = [incus_storage_pool.extra]
}

# 13. Worker VMs
resource "incus_instance" "worker" {
  for_each = toset(local.wk_names)

  project  = var.project
  name     = each.key
  image    = data.incus_image.talos.fingerprint
  type     = "virtual-machine"
  profiles = [incus_profile.talos_vm.name]
  running  = true

  config = {
    "security.secureboot" = "false"
    "limits.cpu"          = var.cpu
    "limits.memory"       = var.worker_memory
    "raw.qemu"            = "-drive file=${var.seed_iso_dir}/${each.key}.iso,if=ide,media=cdrom,format=raw,readonly=on"
  }

  dynamic "device" {
    for_each = var.extra_disk_size != "" ? ["data"] : []
    content {
      name = "sdb"
      type = "disk"
      properties = {
        pool   = incus_storage_pool.extra[0].name
        source = "${each.key}-data"
      }
    }
  }

  depends_on = [
    null_resource.seed_iso,
    incus_profile.talos_vm,
    incus_network.talos_bridge,
    incus_storage_volume.worker_extra,
  ]
}
