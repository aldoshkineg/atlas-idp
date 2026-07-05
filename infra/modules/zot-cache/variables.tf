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

variable "proxy_listen" {
  description = "Proxy listen address, e.g. tcp:10.200.10.1:5000"
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
