output "endpoint" {
  value = var.create_cluster ? kind_cluster.default[0].endpoint : null
}

output "cluster_ca_certificate" {
  value = var.create_cluster ? kind_cluster.default[0].cluster_ca_certificate : null
}

output "client_certificate" {
  value = var.create_cluster ? kind_cluster.default[0].client_certificate : null
}

output "client_key" {
  value = var.create_cluster ? kind_cluster.default[0].client_key : null
}

output "kubeconfig_path" {
  value = var.create_cluster ? kind_cluster.default[0].kubeconfig_path : null
}

output "cluster_name" {
  value = var.create_cluster ? kind_cluster.default[0].name : ""
}

output "cluster_ready" {
  description = "True if the KinD cluster resource is successfully created"
  value       = var.create_cluster ? length(kind_cluster.default) > 0 : false
}
