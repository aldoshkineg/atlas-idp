variable "enable" {
  description = "Enable Zot cache container"
  type        = bool
  default     = true
}

variable "platform" {
  description = "Container runtime: docker or incus"
  type        = string
  default     = "docker"
  validation {
    condition     = contains(["docker", "incus"], var.platform)
    error_message = "Platform must be one of: docker, incus"
  }
}

variable "container_name" {
  description = "Name of the Zot container"
  type        = string
  default     = "kind-zot-registry"
}

variable "port" {
  description = "Port for the Zot registry"
  type        = number
  default     = 5000
}

variable "image_tag" {
  description = "Zot container image tag"
  type        = string
  default     = "v2.1.16"
}

# Docker-specific
variable "network_name" {
  description = "Docker network to attach Zot to"
  type        = string
  default     = "kind"
}

variable "config_dir" {
  description = "Host path for Zot config file (docker only)"
  type        = string
  default     = "/var/tmp/atlas"
}

# Platform-agnostic
variable "cache_dir" {
  description = "Host path for Zot cache storage (mapped to /var/lib/registry)"
  type        = string
  default     = "/var/tmp/atlas/zot_cache/zot-cache-data"
}

# Incus-specific
variable "incus_network" {
  description = "Incus bridge network name (incus only)"
  type        = string
  default     = "incusbr0"
}

variable "incus_proxy_listen" {
  description = "Proxy listen address (incus only), e.g. tcp:10.200.10.1:5000"
  type        = string
  default     = "tcp:10.200.10.1:5000"
}

variable "incus_image_alias" {
  description = "Alias for the Zot image in Incus"
  type        = string
  default     = "zot-cache"
}

variable "incus_image_ref" {
  description = "Remote image reference for incus image copy (e.g. ghcr-oci:project-zot/zot:v2.1.16)"
  type        = string
  default     = "ghcr-oci:project-zot/zot:v2.1.16"
}
