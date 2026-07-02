variable "controlplane_configs" {
  type        = list(string)
  sensitive   = true
  description = "Machine configuration YAMLs for controlplane nodes"
}

variable "worker_configs" {
  type        = list(string)
  sensitive   = true
  description = "Machine configuration YAMLs for worker nodes"
  default     = []
}

variable "client_configuration" {
  type        = any
  sensitive   = true
  description = "Talos client configuration from talos_machine_secrets"
}

variable "cp_ips" {
  type        = list(string)
  description = "Controlplane node IPs"
}

variable "worker_ips" {
  type        = list(string)
  description = "Worker node IPs"
  default     = []
}

variable "files_dir" {
  type        = string
  description = "Directory for generated kubeconfig"
  default     = ""
}

variable "apply_mode" {
  type        = string
  description = "Talos config apply mode (auto, no_reboot, interactive)"
  default     = "auto"
}
