variable "enable" {
  description = "Enable Zot cache container"
  type        = bool
  default     = true
}

variable "port" {
  description = "Zot registry listen port inside the container"
  type        = number
  default     = 5000
}

variable "cache_dir" {
  description = "Host path for Zot cache storage (mapped to /var/lib/registry)"
  type        = string
  default     = "/var/tmp/atlas/zot_cache/zot-cache-data"
}

variable "network" {
  description = "Incus bridge network name"
  type        = string
}

variable "gateway" {
  description = "Bridge gateway IP (used for resolv.conf nameserver)"
  type        = string
}

variable "image_alias" {
  description = "Alias for the Zot image in Incus"
  type        = string
  default     = "zot-cache"
}

variable "image_remote" {
  description = "Incus remote to pull the Zot image from (defined in the incus provider; e.g. an OCI remote named ghcr-oci)"
  type        = string
  default     = "ghcr-oci"
}

variable "image_name" {
  description = "Image name/reference on the remote (e.g. project-zot/zot:v2.1.16)"
  type        = string
  default     = "project-zot/zot:v2.1.16"
}

variable "image_type" {
  description = "Image type to cache (container or virtual-machine)"
  type        = string
  default     = "container"
}

variable "static_ip" {
  description = "Static IPv4 address for the Zot container (e.g. 10.200.10.2)"
  type        = string
  default     = "10.200.10.2"
}
