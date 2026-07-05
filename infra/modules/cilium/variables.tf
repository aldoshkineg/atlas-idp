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

variable "envoy_image_tag" {
  description = "Tag for Cilium Envoy sidecar image"
  type        = string
  default     = "v1.34.4-1753677767-266d5a01d1d55bd1d60148f991b98dac0390d363"
}

variable "certgen_image_tag" {
  description = "Tag for Cilium certgen init container image"
  type        = string
  default     = "v0.2.4"
}

variable "hubble_ui_backend_tag" {
  description = "Tag for Hubble UI backend image"
  type        = string
  default     = "v0.13.2"
}

variable "hubble_ui_frontend_tag" {
  description = "Tag for Hubble UI frontend image"
  type        = string
  default     = "v0.13.2"
}
