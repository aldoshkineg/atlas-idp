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
  description = "Alias of the Zot image in Incus (created by Terraform via null_resource.import_zot)"
  type        = string
  default     = "zot-cache"
}

variable "image_ref" {
  description = "Full source reference of the Zot image (registry/repo:tag)"
  type        = string
  default     = "ghcr.io/project-zot/zot:v2.1.16"
}

variable "image_registry" {
  description = "Registry host prefix stripped from image_ref to build the OCI remote path"
  type        = string
  default     = "ghcr.io"
}

variable "image_remote" {
  description = "Incus OCI remote name used to copy the image"
  type        = string
  default     = "ghcr-oci"
}

variable "image_registry_url" {
  description = "OCI registry URL for the Incus remote"
  type        = string
  default     = "https://ghcr.io"
}

variable "static_ip" {
  description = "Static IPv4 address for the Zot container (e.g. 10.200.10.2)"
  type        = string
  default     = "10.200.10.2"
}
