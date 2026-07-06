# === Cluster ===

variable "cluster_name" {
  description = "Talos/Kubernetes cluster name"
  type        = string
  default     = "talos-incus"
}

variable "cluster_vip" {
  description = "Cluster VIP for multi-CP setups (disabled when controlplane_count <= 1)"
  type        = string
  default     = "10.200.10.10"

  validation {
    condition     = var.cluster_vip == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.cluster_vip))
    error_message = "cluster_vip must be a valid IPv4 address or empty."
  }
}

variable "controlplane_count" {
  description = "Number of controlplane nodes (auto-generates cp_ips when cp_ips is empty)"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes (auto-generates worker_ips from cluster_cidr when worker_ips is empty)"
  type        = number
  default     = 2
}

variable "cp_ips" {
  description = "Controlplane node IPs (auto-generated from controlplane_count when empty)"
  type        = list(string)
  default     = []
}

variable "worker_ips" {
  description = "Worker node IPs (auto-generated from cluster_cidr when empty)"
  type        = list(string)
  default     = []
}

# === Network ===

variable "gateway" {
  description = "Network gateway address"
  type        = string
  default     = "10.200.10.1"

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway))
    error_message = "gateway must be a valid IPv4 address."
  }
}

variable "cluster_cidr" {
  description = "Cluster pod/service CIDR for kubelet nodeIP"
  type        = string
  default     = "10.200.10.0/24"

  validation {
    condition     = can(cidrhost(var.cluster_cidr, 0))
    error_message = "cluster_cidr must be a valid CIDR notation (e.g. 10.200.10.0/24)."
  }
}

# === Versions ===

variable "talos_version" {
  description = "Talos OS version"
  type        = string
  default     = "v1.11.2"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.34.1"
}

variable "cilium_chart_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.4"
}

variable "pause_image" {
  description = "Sandbox (pause) image for containerd CRI"
  type        = string
  default     = "ghcr.io/aldoshkineg/pause:3.10-amd64"
}

variable "skip_fallback" {
  description = "Prevent falling back to upstream registries when mirror is unreachable"
  type        = bool
  default     = true
}

# === Cilium LoadBalancer IP Pool ===

variable "lb_pool_start" {
  description = "Start of the LoadBalancer IP pool range (auto-derived from cluster_cidr when empty)"
  type        = string
  default     = ""

  validation {
    condition     = var.lb_pool_start == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.lb_pool_start))
    error_message = "lb_pool_start must be a valid IPv4 address or empty."
  }
}

variable "lb_pool_end" {
  description = "End of the LoadBalancer IP pool range (auto-derived from cluster_cidr when empty)"
  type        = string
  default     = ""

  validation {
    condition     = var.lb_pool_end == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.lb_pool_end))
    error_message = "lb_pool_end must be a valid IPv4 address or empty."
  }
}

# === Paths ===

variable "talos_image_path" {
  description = "Local path for the Talos qcow2 image (downloaded if missing)"
  type        = string
  default     = "/var/tmp/atlas/incus/talos-drbd.qcow2"
}

variable "files_dir" {
  description = "Directory for generated Talos configs, kubeconfig, and talosconfig"
  type        = string
  default     = "/var/tmp/atlas/talos"
}

variable "seed_iso_dir" {
  description = "Directory for seed ISO staging"
  type        = string
  default     = "/var/tmp/atlas/incus/seed"
}

# === Zot Registry Cache ===

variable "zot_enable" {
  description = "Enable Zot registry cache container"
  type        = bool
  default     = true
}

variable "zot_cache_dir" {
  description = "Zot registry cache directory on the host"
  type        = string
  default     = "/var/tmp/atlas/zot_cache/zot-cache-data"
}

variable "zot_image_ref" {
  description = "Zot OCI image reference for Incus image copy"
  type        = string
  default     = "ghcr-oci:project-zot/zot:v2.1.16"
}

variable "zot_port" {
  description = "Zot registry listen port"
  type        = number
  default     = 5000
}

variable "zot_address" {
  description = "Zot container static IP address (for routed NIC)"
  type        = string
  default     = "10.200.10.2"

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.zot_address))
    error_message = "zot_address must be a valid IPv4 address."
  }
}

# === VM Resources ===

variable "cp_memory" {
  description = "Controlplane VM memory"
  type        = string
  default     = "4GiB"
}

variable "worker_memory" {
  description = "Worker VM memory"
  type        = string
  default     = "5GiB"
}

variable "vm_cpu" {
  description = "VM CPU count (applied to all nodes)"
  type        = string
  default     = "4"
}

variable "vm_disk_size" {
  description = "Root disk size for each Talos VM"
  type        = string
  default     = "10GiB"
}

variable "worker_extra_disk" {
  description = "Extra disk size for worker VMs (e.g. 5GiB for LINSTOR). Empty string to disable."
  type        = string
  default     = "5GiB"
}

variable "extra_pool_size" {
  description = "Total size of the LVM pool for extra worker disks"
  type        = string
  default     = "15GiB"
}

variable "root_app_path" {
  description = "Path to the GitOps root Application manifest"
  type        = string
  default     = ""

  validation {
    condition     = var.root_app_path == "" || can(file(var.root_app_path))
    error_message = "root_app_path must point to an existing file or be empty to use the default path."
  }
}
