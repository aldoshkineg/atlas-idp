variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "kind"
}

variable "create_cluster" {
  description = "Whether to create the kind cluster using Terraform"
  type        = bool
  default     = true
}

variable "worker_node_count" {
  description = "Number of worker nodes in the cluster"
  type        = number
  default     = 1
}

variable "control_plane_nodes" {
  description = "List of control plane node configurations"
  type = list(object({
    role = string
  }))
  default = [
    {
      role = "control-plane"
    }
  ]
}

variable "ingress_ready" {
  description = "Whether to label the control-plane node as ingress-ready"
  type        = bool
  default     = false
}

variable "extra_port_mappings" {
  description = "Extra port mappings for the control-plane node"
  type = list(object({
    container_port = number
    host_port      = number
    protocol       = optional(string, "TCP")
  }))
  default = []
}

variable "kind_config_path" {
  description = "Path to the kind configuration file (optional, not used with kind provider)"
  type        = string
  default     = ""
  deprecated  = "This variable is not used with the kind provider. Configuration is done via kind_config block."
}

variable "kubernetes_version" {
  description = "Kubernetes version to use (e.g., v1.27.0). Requires matching node image."
  type        = string
  default     = ""
}
