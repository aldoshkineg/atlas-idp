variable "enable" {
  description = "Enable Zot cache container"
  type        = bool
  default     = true
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

variable "network_name" {
  description = "Docker network to attach Zot to"
  type        = string
  default     = "kind"
}

variable "cache_dir" {
  description = "Host path for Zot cache storage (mapped to /var/lib/registry)"
  type        = string
  default     = "/var/tmp/atlas/zot_cache/zot-cache-data"
}

variable "config_dir" {
  description = "Host path for Zot config file"
  type        = string
  default     = "/var/tmp/atlas"
}
