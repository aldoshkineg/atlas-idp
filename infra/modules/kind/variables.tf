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

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/kind"
}

variable "worker_node_count" {
  description = "Number of worker nodes in the cluster"
  type        = number
  default     = 1

  validation {
    condition     = var.worker_node_count >= 0
    error_message = "worker_node_count must be zero or greater."
  }
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

  validation {
    condition     = alltrue([for mapping in var.extra_port_mappings : contains(["TCP", "UDP", "SCTP"], upper(mapping.protocol))])
    error_message = "extra_port_mappings.protocol must be one of TCP, UDP or SCTP."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to use (e.g., v1.27.0). Requires matching node image."
  type        = string
  default     = "v1.35.0"
}

variable "enable_cache" {
  description = "Enable containerd registry mirroring/cache through Zot"
  type        = bool
  default     = false
}

variable "cache_registry_server" {
  description = "Upstream registry server URL for containerd"
  type        = string
  default     = "https://zot-registry.local"
}

variable "cache_host_url" {
  description = "Zot cache proxy URL inside the Docker network"
  type        = string
  default     = "http://kind-zot-registry:5000"
}

variable "cache_host_capabilities" {
  description = "Containerd operations allowed for the cache host"
  type        = list(string)
  default     = ["pull", "resolve"]
}

variable "disable_default_cni" {
  description = "Disable kindnet and kube-proxy to install Cilium"
  type        = bool
  default     = false
}
