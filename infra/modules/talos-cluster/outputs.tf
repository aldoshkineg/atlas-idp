output "kubeconfig_raw" {
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
  description = "Kubeconfig content for connecting to the cluster"
}

output "kubeconfig_path" {
  value       = local_sensitive_file.kubeconfig.filename
  description = "Path to the kubeconfig file on disk"
}
