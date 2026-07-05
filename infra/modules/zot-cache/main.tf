# Incus: copy image from OCI registry (skipped if already present)
resource "null_resource" "zot_image" {
  count = var.enable ? 1 : 0

  triggers = {
    image_ref = var.image_ref
    alias     = var.image_alias
  }

  provisioner "local-exec" {
    command = <<-CMD
      if incus image info "${self.triggers["alias"]}" >/dev/null 2>&1; then
        echo "Image ${self.triggers["alias"]} already present, skipping copy"
      else
        incus image copy "${self.triggers["image_ref"]}" local: --alias "${self.triggers["alias"]}"
      fi
    CMD
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "echo 'Preserving Incus image ${self.triggers["alias"]} for next use'"
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
      network = var.network
    }
  }

  device {
    name = "zot-port"
    type = "proxy"
    properties = {
      listen  = var.proxy_listen
      connect = "tcp:127.0.0.1:${var.port}"
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
}
