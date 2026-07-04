# 1. Managed Incus bridge (NAT + DHCP + DNS)
resource "null_resource" "bridge_setup" {
  triggers = {
    bridge_name = var.bridge_name
    subnet      = var.bridge_subnet
  }

  provisioner "local-exec" {
    command = <<-EOT
      if ! incus network show "${var.bridge_name}" >/dev/null 2>&1; then
        incus network create "${var.bridge_name}" \
          ipv4.address="${var.bridge_subnet}" \
          ipv4.nat=true \
          ipv4.dhcp=false \
          ipv6.address=none
      else
        incus network set "${var.bridge_name}" ipv4.dhcp=false
      fi
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "incus network delete '${self.triggers["bridge_name"]}' 2>/dev/null; true"
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
      parent  = var.bridge_name
    }
  }
}

# 3. Download + import Talos image with metadata tarball
resource "null_resource" "import_image" {
  triggers = {
    image_path = var.talos_image_file
    image_url  = var.talos_image_url
    alias      = var.image_alias
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      if [ ! -f '${var.talos_image_file}' ]; then
        echo "=== Downloading from ${var.talos_image_url} ==="
        mkdir -p "$(dirname '${var.talos_image_file}')"
        curl -L -o '${var.talos_image_file}' '${var.talos_image_url}'
      fi

      TMP_DIR=$(mktemp -d)
      cat <<EOF > "$TMP_DIR/metadata.yaml"
architecture: "x86_64"
creation_date: $(date +%s)
properties:
  description: "Talos OS Cloud-Native Image"
  os: "talos"
  type: "virtual-machine"
EOF
      tar -czf "$TMP_DIR/metadata.tar.gz" -C "$TMP_DIR" metadata.yaml

      echo "=== Importing image with alias '${var.image_alias}' ==="
      incus image delete '${var.image_alias}' 2>/dev/null || true
      incus image import "$TMP_DIR/metadata.tar.gz" '${var.talos_image_file}' --alias '${var.image_alias}'

      rm -rf "$TMP_DIR"
    EOT
  }
}

# 4. Image data source (resolves fingerprint)
data "incus_image" "talos" {
  depends_on = [null_resource.import_image]
  name       = var.image_alias
  project    = var.project
}

# 5. VM name derivation
locals {
  cp_names = [for i in range(nonsensitive(length(var.controlplane_configs))) : "${var.cluster_name}-cp-${i + 1}"]
  wk_count = nonsensitive(length(var.worker_configs))
  wk_names = [for i in range(local.wk_count) : "${var.cluster_name}-worker-${i + 1}"]

  vm_configs = merge(
    { for i, name in local.cp_names : name => var.controlplane_configs[i] },
    { for i, name in local.wk_names : name => var.worker_configs[i] },
  )
}

# 6. Seed ISO user-data / meta-data files
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

# 7. Seed ISO assembly
resource "null_resource" "seed_iso" {
  for_each = local.vm_configs

  depends_on = [
    local_sensitive_file.user_data,
    local_file.meta_data,
  ]

  triggers = {
    user_data_sha256 = sha256(each.value)
    meta_data_sha256 = sha256("instance-id: ${each.key}\nlocal-hostname: ${each.key}")
  }

  provisioner "local-exec" {
    command = "xorriso -as mkisofs -r -V cidata -J -o '${var.seed_iso_dir}/${each.key}.iso' '${var.seed_iso_dir}/${each.key}/'"
  }
}

# 8. Controlplane VMs
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
    null_resource.bridge_setup,
  ]
}

# 9. LVM storage pool for block volumes (used by worker extra disks)
resource "incus_storage_pool" "extra" {
  count  = var.extra_disk_size != "" ? 1 : 0
  name   = "extra-pool"
  driver = "lvm"

  config = {
    size               = "15GiB"
    "lvm.vg_name"      = "incus-extra"
    "lvm.use_thinpool" = "false"
  }
}

# 10. Worker extra storage volumes (for LINSTOR)
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

# 11. Worker VMs
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
    null_resource.bridge_setup,
    incus_storage_volume.worker_extra,
  ]
}
