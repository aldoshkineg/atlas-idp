# Incus: the Zot image is NOT managed by Terraform.
#
# The image is provisioned once, outside Terraform, via the `make zot-image`
# hook (it copies ghcr.io/project-zot/zot into Incus under the alias
# "zot-cache" only when that alias is missing). Terraform then launches the
# container by that alias and manages only the instance. This keeps
# `terraform destroy` clean: it removes the instance but never touches the
# image, so the cache survives across destroy/apply cycles.
#
# Incus: Zot container instance
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
}
