variable "cilium_chart_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.4"
}

variable "cluster_name" {
  description = "Name of the cluster (used for control-plane container hostname fallback)"
  type        = string
}

variable "k8s_service_host" {
  description = "Kubernetes API server hostname/IP for Cilium. Falls back to <cluster_name>-control-plane if empty."
  type        = string
  default     = ""
}

variable "k8s_service_port" {
  description = "Kubernetes API server port for Cilium (default 6443, use 7445 for Talos KubePrism)"
  type        = string
  default     = "6443"
}

variable "cilium_settings" {
  description = "Additional Cilium Helm set values. Optionally specify type (auto/string/list) for list-capability values."
  type = list(object({
    name  = string
    value = string
    type  = optional(string, "string")
  }))
  default = []

  validation {
    condition     = alltrue([for setting in var.cilium_settings : setting.name != ""]) && length(distinct([for setting in var.cilium_settings : setting.name])) == length(var.cilium_settings)
    error_message = "cilium_settings must not contain empty or duplicate setting names."
  }
}

variable "talos" {
  description = "Enable Talos-specific Cilium settings (privileged init containers, CRD identity allocation)"
  type        = bool
  default     = false
}
