output "image_alias" {
  description = "Alias assigned to the Zot image"
  value       = var.enable ? var.image_alias : null
}

output "container_name" {
  value = var.enable ? incus_instance.zot[0].name : null
}

output "port" {
  value = var.port
}

output "network" {
  value = var.network
}

output "ip_address" {
  value = var.enable ? incus_instance.zot[0].ipv4_address : null
}
