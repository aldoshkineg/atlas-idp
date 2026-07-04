variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster name prefix for VM naming"
}

variable "talos_image_file" {
  type        = string
  description = "Local path for the Talos qcow2 image (downloaded if missing)"
}

variable "talos_image_url" {
  type        = string
  description = "URL to download the Talos qcow2 image if not present locally"
  default     = "https://github.com/siderolabs/talos/releases/download/v1.11.2/ncloud-amd64.qcow2"
}

variable "image_alias" {
  type        = string
  description = "Incus image alias"
  default     = "talos-drbd"
}

variable "bridge_name" {
  type        = string
  description = "Incus managed bridge name"
  default     = "incusbr0"
}

variable "bridge_subnet" {
  type        = string
  description = "Bridge subnet with mask (CIDR)"
  default     = "10.200.10.1/24"
}

variable "project" {
  type        = string
  description = "Incus project"
  default     = "default"
}

variable "controlplane_configs" {
  type        = list(string)
  sensitive   = true
  description = "Talos machine config YAMLs for controlplane nodes (one per instance)"
}

variable "worker_configs" {
  type        = list(string)
  sensitive   = true
  description = "Talos machine config YAMLs for worker nodes"
  default     = []
}

variable "cp_memory" {
  type    = string
  default = "2GiB"
}

variable "worker_memory" {
  type    = string
  default = "2GiB"
}

variable "cpu" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "10GiB"
}

variable "extra_disk_size" {
  type        = string
  description = "Extra disk size for worker VMs (e.g. 5GiB). Empty string to disable."
  default     = ""
}

variable "seed_iso_dir" {
  type        = string
  description = "Directory for seed ISO staging"
  default     = "/var/tmp/atlas/incus/seed"
}
