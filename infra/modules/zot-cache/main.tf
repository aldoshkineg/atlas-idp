# Incus: pull the Zot image from the ghcr-oci OCI remote via the incus provider.
#
# The image is a cache that survives `stage-destroy`: the destroy script preserves
# the image in Incus and wipes Terraform state, but never deletes the image. When
# Incus copies the published OCI image it force-sets the source alias "zot-cache"
# locally, which collides with the preserved image on a re-apply (the incus_image
# resource has no import support, so it cannot adopt the existing image). The apply
# pipeline therefore clears the stale "zot-cache" alias (keeping the image itself)
# before `terraform apply`; Incus then reuses the existing image by fingerprint
# instead of re-downloading, and re-applies the alias. The instance references the
# image by fingerprint.
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
