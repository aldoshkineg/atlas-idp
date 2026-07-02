output "container_name" {
  value = var.enable ? (
    var.platform == "docker" ? docker_container.zot[0].name : incus_instance.zot[0].name
  ) : null
}

output "port" {
  value = var.port
}

output "network" {
  value = var.platform == "docker" ? data.docker_network.kind[0].name : var.incus_network
}
