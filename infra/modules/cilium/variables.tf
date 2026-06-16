variable "cilium_chart_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.4"
}

variable "cluster_name" {
  description = "Name of the kind cluster (used for control-plane container hostname)"
  type        = string
}

variable "cilium_settings" {
  description = "Additional Cilium Helm set values"
  type = list(object({
    name  = string
    value = string
  }))
  default = []

  validation {
    condition     = alltrue([for setting in var.cilium_settings : setting.name != ""]) && length(distinct([for setting in var.cilium_settings : setting.name])) == length(var.cilium_settings)
    error_message = "cilium_settings must not contain empty or duplicate setting names."
  }
}
