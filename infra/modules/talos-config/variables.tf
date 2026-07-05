variable "cluster_name" {
  type        = string
  description = "Talos/Kubernetes cluster name"
}

variable "talos_version" {
  type        = string
  description = "Talos OS version"
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version for Talos kubelet and control plane images"
}

variable "gateway" {
  type        = string
  description = "Network gateway address (used as Zot mirror endpoint)"
}

variable "cluster_cidr" {
  type        = string
  description = "Cluster pod/service CIDR for kubelet nodeIP validSubnets"
}

variable "cp_ips" {
  type        = list(string)
  description = "Controlplane node IPs (auto-generated from controlplane_count when empty)"
  default     = []
}

variable "worker_ips" {
  type        = list(string)
  description = "Worker node IPs"
}

variable "cluster_vip" {
  type        = string
  description = "Cluster VIP for multi-CP setups (disabled when <= 1 controlplane)"
  default     = ""
}

variable "controlplane_count" {
  type        = number
  description = "Number of controlplane nodes (used when cp_ips is empty)"
  default     = 1
}

variable "files_dir" {
  type        = string
  description = "Directory for generated Talos configs, kubeconfig, and talosconfig"
}

variable "pause_image" {
  type        = string
  description = "Sandbox (pause) image for containerd CRI"
  default     = "registry.k8s.io/pause:3.10"
}

variable "api_server_port" {
  type        = number
  description = "Kubernetes API server port (default 6443)"
  default     = 6443
}

variable "skip_fallback" {
  type        = bool
  description = "Prevent falling back to upstream registries when mirror is unreachable"
  default     = true
}
