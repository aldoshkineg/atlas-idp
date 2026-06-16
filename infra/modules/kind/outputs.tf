# Reusable cluster reference
locals {
  cluster       = var.create_cluster ? kind_cluster.default[0] : null
  cluster_name  = local.cluster != null ? local.cluster.name : ""
  cluster_ready = local.cluster != null
}

output "endpoint" {
  description = "Kubernetes API server endpoint"
  value       = local.cluster != null ? local.cluster.endpoint : null
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = local.cluster != null ? local.cluster.cluster_ca_certificate : null
}

output "client_certificate" {
  description = "Base64-encoded client certificate"
  value       = local.cluster != null ? local.cluster.client_certificate : null
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client key"
  value       = local.cluster != null ? local.cluster.client_key : null
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = local.cluster != null ? local.cluster.kubeconfig_path : null
}

output "cluster_name" {
  description = "Name of the kind cluster"
  value       = local.cluster_name
}

output "cluster_ready" {
  description = "True if the KinD cluster resource is successfully created"
  value       = local.cluster_ready
}
