variable "cluster_name" {
  description = "kind cluster name"
  type        = string
  default     = "atlas-idp"
}

variable "argocd_namespace" {
  description = "Namespace for Argo CD"
  type        = string
  default     = "argocd"
}
