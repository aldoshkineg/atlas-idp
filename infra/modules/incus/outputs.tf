output "bridge_name" {
  value       = var.bridge_name
  description = "Manual bridge name"
}

output "image_alias" {
  value       = var.image_alias
  description = "Imported image alias"
}

output "image_fingerprint" {
  value       = data.incus_image.talos.fingerprint
  description = "Imported image fingerprint"
}

output "controlplane_names" {
  value       = [for vm in incus_instance.controlplane : vm.name]
  description = "Controlplane VM names"
}

output "worker_names" {
  value       = [for vm in incus_instance.worker : vm.name]
  description = "Worker VM names"
}

output "profile_name" {
  value       = incus_profile.talos_vm.name
  description = "VM profile name"
}
