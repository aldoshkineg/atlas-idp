variable "cilium_chart_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.4"
}

variable "cluster_name" {
  description = "Name of the kind cluster (used for control-plane container hostname)"
  type        = string
}
