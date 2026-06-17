output "container_name" {
  value = var.enable ? docker_container.zot[0].name : null
}

output "port" {
  value = var.port
}

output "network" {
  value = data.docker_network.kind.name
}
