output "endpoint" {
  description = "Kubernetes API server endpoint"
  value       = var.create_cluster ? kind_cluster.default[0].endpoint : null
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = var.create_cluster ? kind_cluster.default[0].cluster_ca_certificate : null
}

output "client_certificate" {
  description = "Base64-encoded client certificate"
  value       = var.create_cluster ? kind_cluster.default[0].client_certificate : null
}

output "client_key" {
  description = "Base64-encoded client key"
  value       = var.create_cluster ? kind_cluster.default[0].client_key : null
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = var.create_cluster ? kind_cluster.default[0].kubeconfig_path : null
}

output "cluster_name" {
  description = "Name of the kind cluster"
  value       = var.create_cluster ? kind_cluster.default[0].name : ""
}

output "cluster_ready" {
  description = "True if the KinD cluster resource is successfully created"
  value       = var.create_cluster ? length(kind_cluster.default) > 0 : false
}
