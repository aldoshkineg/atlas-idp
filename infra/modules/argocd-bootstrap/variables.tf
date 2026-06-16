variable "argocd_namespace" {
  description = "Namespace for Argo CD installation"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "7.7.5"
}

variable "argocd_values_override" {
  description = "Custom values for Argo CD Helm chart (YAML string)"
  type        = string
  default     = ""
}

variable "create_namespace" {
  description = "Whether to create the Argo CD namespace"
  type        = bool
  default     = true
}

variable "insecure_mode" {
  description = "Run Argo CD server in insecure mode (HTTP, for local dev)"
  type        = bool
  default     = true
}

variable "argocd_node_port_http" {
  description = "NodePort used by Argo CD server for local kind access"
  type        = number
  default     = 30080

  validation {
    condition     = var.argocd_node_port_http >= 30000 && var.argocd_node_port_http <= 32767
    error_message = "argocd_node_port_http must be a valid Kubernetes NodePort between 30000 and 32767."
  }
}

variable "admin_password_bcrypt" {
  description = "BCrypt hash of admin password (optional, generates random if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "repo_url" {
  description = "GitHub repository URL for GitOps source"
  type        = string
  default     = ""
}

variable "repo_type" {
  description = "Repository type (git, helm, etc)"
  type        = string
  default     = "git"

  validation {
    condition     = contains(["git", "helm", "oci"], lower(var.repo_type))
    error_message = "repo_type must be one of git, helm or oci."
  }
}
