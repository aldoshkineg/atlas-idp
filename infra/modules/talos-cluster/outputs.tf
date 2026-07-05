output "kubeconfig_raw" {
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
  description = "Kubeconfig content for connecting to the cluster"
}

output "kubeconfig_path" {
  value       = local_sensitive_file.kubeconfig.filename
  description = "Path to the kubeconfig file on disk"
}

output "kubernetes_client_config" {
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
  description = "Kubernetes client configuration (host, CA, certs) for provider config"
}
