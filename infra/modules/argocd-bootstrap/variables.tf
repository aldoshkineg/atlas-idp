variable "argocd_namespace" {
  description = "Namespace for Argo CD installation"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "9.5.15" # Stable version from argo-helm repo
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
}
