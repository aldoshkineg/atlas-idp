locals {
  config_path = abspath("${path.module}/zot-config.json")
}

data "docker_network" "kind" {
  count = var.platform == "docker" && var.enable ? 1 : 0
  name  = var.network_name
}

resource "docker_image" "zot" {
  count = var.platform == "docker" && var.enable ? 1 : 0

  name         = "ghcr.io/project-zot/zot:${var.image_tag}"
  keep_locally = true
}

resource "local_file" "zot_config" {
  count = var.platform == "docker" && var.enable ? 1 : 0

  content  = file(local.config_path)
  filename = "${var.config_dir}/zot_config.json"
}

resource "docker_container" "zot" {
  count = var.platform == "docker" && var.enable ? 1 : 0

  name    = var.container_name
  image   = docker_image.zot[0].name
  restart = "always"

  networks_advanced {
    name = data.docker_network.kind[0].name
  }

  ports {
    internal = var.port
    external = var.port
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = local_file.zot_config[0].filename
    container_path = "/etc/zot/config.json"
    read_only      = true
  }

  volumes {
    host_path      = var.cache_dir
    container_path = "/var/lib/registry"
  }

  ulimit {
    name = "nofile"
    soft = 65535
    hard = 65535
  }
}

# Incus: copy image from OCI registry (skipped if already present)
resource "null_resource" "zot_image" {
  count = var.platform == "incus" && var.enable ? 1 : 0

  triggers = {
    image_ref = var.incus_image_ref
    alias     = var.incus_image_alias
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
# (Zot creates .sync dirs for on-demand syncs; if the container is
# destroyed mid-sync, they persist and confuse the new instance)
resource "null_resource" "cleanup_sync" {
  count = var.platform == "incus" && var.enable ? 1 : 0

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
  count = var.platform == "incus" && var.enable ? 1 : 0

  depends_on = [null_resource.zot_image, null_resource.cleanup_sync]

  name    = var.incus_image_alias
  image   = var.incus_image_alias
  type    = "container"
  running = true

  config = {
    "security.privileged" = "true"
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      network = var.incus_network
    }
  }

  device {
    name = "zot-port"
    type = "proxy"
    properties = {
      listen  = var.incus_proxy_listen
      connect = "tcp:127.0.0.1:${var.port}"
    }
  }

  device {
    name = "config"
    type = "disk"
    properties = {
      source   = local.config_path
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
