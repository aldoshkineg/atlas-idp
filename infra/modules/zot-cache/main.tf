# Incus: pull the Zot image from a remote (natively; idempotent via TF state).
# For an OCI remote (e.g. ghcr-oci -> https://ghcr.io) Incus uses skopeo under
# the hood. The remote must be declared in the incus provider configuration.
resource "incus_image" "zot" {
  count = var.enable ? 1 : 0

  source_image = {
    remote = var.image_remote
    name   = var.image_name
    type   = var.image_type
  }

  alias {
    name = var.image_alias
  }
}

# Clean stale .sync directories from previous container runs
resource "null_resource" "cleanup_sync" {
  count = var.enable ? 1 : 0

  triggers = {
    cache_dir = var.cache_dir
  }

  provisioner "local-exec" {
    command = "rm -rf \"${var.cache_dir}\"/*/.sync \"${var.cache_dir}\"/*/*/.sync \"${var.cache_dir}\"/*/*/*/.sync 2>/dev/null; true"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Preserving cache for next use'"
  }
}

# Incus: Zot container instance
resource "incus_instance" "zot" {
  count = var.enable ? 1 : 0

  depends_on = [incus_image.zot, null_resource.cleanup_sync]

  name    = var.image_alias
  image   = incus_image.zot[0].fingerprint
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
}
