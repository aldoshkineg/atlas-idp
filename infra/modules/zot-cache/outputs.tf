output "container_name" {
  value = var.enable ? incus_instance.zot[0].name : null
}

output "port" {
  value = var.port
}

output "network" {
  value = var.network
}
