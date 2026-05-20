# kind cluster is created via clusters/scripts; this module tracks metadata
# and optional post-create hooks for local-kind environment.

variable "cluster_name" {
  type = string
}

output "cluster_name" {
  value = var.cluster_name
}

output "kube_context" {
  value = "kind-${var.cluster_name}"
}
