# Incus: Zot OCI pull-through registry cache.
#
# The Zot image is fully managed by Terraform (variant ii) using only the
# already-required `incus` CLI: a null_resource ensures a ghcr.io OCI remote
# exists and copies the pinned image into Incus under the "zot-cache" alias —
# but ONLY when that alias is absent, so `terraform apply` never re-downloads
# the image on subsequent runs. There is deliberately NO destroy provisioner,
# so `terraform destroy` removes only the container instance and never the
# image, letting the cache survive across destroy/apply cycles.

# 1. Ensure the Zot image is present in Incus (idempotent: skip if alias exists).
resource "null_resource" "import_zot" {
  triggers = {
    image_ref          = var.image_ref
    image_registry     = var.image_registry
    image_remote       = var.image_remote
    image_registry_url = var.image_registry_url
    image_alias        = var.image_alias
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      if incus image show '${var.image_alias}' >/dev/null 2>&1; then
        echo "=== Incus image alias '${var.image_alias}' already present, skipping import ==="
        exit 0
      fi
      echo "=== Ensuring OCI remote '${var.image_remote}' (${var.image_registry_url}) ==="
      incus remote list | grep -qw '${var.image_remote}' || \
        incus remote add '${var.image_remote}' '${var.image_registry_url}' --protocol oci --public
      echo "=== Copying ${var.image_ref} into Incus as '${var.image_alias}' ==="
      incus image copy '${var.image_remote}:${local.image_path}' --alias '${var.image_alias}'
    EOT
  }
}

# 2. Incus: Zot container instance
resource "incus_instance" "zot" {
  count = var.enable ? 1 : 0

  name    = var.image_alias
  image   = var.image_alias
  type    = "container"
  running = true

  config = {
    "security.privileged" = "true"
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      nictype        = "routed"
      parent         = var.network
      "ipv4.address" = var.static_ip
    }
  }

  device {
    name = "config"
    type = "disk"

    properties = {
      source   = abspath("${path.module}/zot-config.json")
      path     = "/etc/zot/config.json"
      readonly = "true"
    }
  }

  device {
    name = "cache"
    type = "disk"

    properties = {
      source = var.cache_dir
      path   = "/var/lib/registry"
    }
  }

  file {
    content     = "nameserver ${var.gateway}\nnameserver 8.8.8.8\n"
    target_path = "/etc/resolv.conf"
    mode        = "0644"
  }

  depends_on = [null_resource.import_zot]
}

locals {
  # Strip the registry host from the full reference to get the OCI remote path,
  # e.g. "ghcr.io/project-zot/zot:v2.1.16" -> "project-zot/zot:v2.1.16".
  image_path = replace(var.image_ref, "${var.image_registry}/", "")
}
