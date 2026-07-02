output "cp_ips" {
  value       = local.cp_ips
  description = "Resolved controlplane IPs"
}

output "worker_ips" {
  value       = var.worker_ips
  description = "Worker node IPs (pass-through)"
}

output "cp_endpoint" {
  value       = local.cp_endpoint
  description = "Cluster endpoint URL"
}

output "cp_configs" {
  value       = local.cp_config_list
  sensitive   = true
  description = "Rendered Talos machine configs for controlplane nodes"
}

output "worker_configs" {
  value       = local.worker_config_list
  sensitive   = true
  description = "Rendered Talos machine configs for worker nodes"
}

output "client_configuration" {
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
  description = "Client configuration from talos_machine_secrets"
}

output "talos_config_path" {
  value       = local_sensitive_file.talosconfig.filename
  description = "Path to the saved talosconfig file"
}
