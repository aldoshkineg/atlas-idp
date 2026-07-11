# Incus: pull the Zot image from a remote, idempotently.
#
# The Zot image is treated as a cache that survives `stage-destroy` (the destroy
# script preserves the alias). A plain `incus_image` resource errors with
# "Image alias already exists" on a re-apply after destroy, so we copy it via the
# incus CLI only when the alias is missing. The incus provider does not expose its
# remote config to the CLI, so the remote is registered here when absent.
resource "null_resource" "zot_image" {
  count = var.enable ? 1 : 0

  triggers = {
    alias  = var.image_alias
    remote = var.image_remote
    url    = var.image_remote_url
    name   = var.image_name
    type   = var.image_type
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      if ! incus remote show "${var.image_remote}" >/dev/null 2>&1; then
        incus remote add "${var.image_remote}" "${var.image_remote_url}" \
          --protocol "${var.image_remote_protocol}" --public
      fi
      if incus image show "${var.image_alias}" >/dev/null 2>&1; then
        echo "Zot image alias '${var.image_alias}' already present, skipping copy"
      else
        echo "Copying Zot image from ${var.image_remote}:${var.image_name} ..."
        incus image copy "${var.image_remote}:${var.image_name}" --alias "${var.image_alias}"
      fi
    EOT
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

  depends_on = [null_resource.zot_image, null_resource.cleanup_sync]

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
}
