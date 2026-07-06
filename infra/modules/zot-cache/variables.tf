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

variable "image_ref" {
  description = "Remote image reference for incus image copy (e.g. ghcr-oci:project-zot/zot:v2.1.16)"
  type        = string
  default     = "ghcr-oci:project-zot/zot:v2.1.16"
}

variable "static_ip" {
  description = "Static IPv4 address for the Zot container (e.g. 10.200.10.2)"
  type        = string
  default     = "10.200.10.2"
}
