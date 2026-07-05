locals {
  config_path = abspath("${path.module}/zot-config.json")
}

data "docker_network" "kind" {
  count = var.enable ? 1 : 0
  name  = var.network_name
}

resource "docker_image" "zot" {
  count = var.enable ? 1 : 0

  name         = "ghcr.io/project-zot/zot:${var.image_tag}"
  keep_locally = true
}

resource "local_file" "zot_config" {
  count = var.enable ? 1 : 0

  content  = file(local.config_path)
  filename = "${var.config_dir}/zot_config.json"
}

resource "docker_container" "zot" {
  count = var.enable ? 1 : 0

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
