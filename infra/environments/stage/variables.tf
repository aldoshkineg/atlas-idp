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
}

variable "controlplane_count" {
  description = "Number of controlplane nodes (auto-generates cp_ips when cp_ips is empty)"
  type        = number
  default     = 1
}

variable "cp_ips" {
  description = "Controlplane node IPs (auto-generated from controlplane_count when empty)"
  type        = list(string)
  default     = []
}

variable "worker_ips" {
  description = "Worker node IPs"
  type        = list(string)
  default     = ["10.200.10.20", "10.200.10.21"]
}

# === Network ===

variable "gateway" {
  description = "Network gateway address"
  type        = string
  default     = "10.200.10.1"
}

variable "cluster_cidr" {
  description = "Cluster pod/service CIDR for kubelet nodeIP"
  type        = string
  default     = "10.200.10.0/24"
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
  default     = "1.18.0"
}

# === Cilium LoadBalancer IP Pool ===

variable "lb_pool_start" {
  description = "Start of the LoadBalancer IP pool range"
  type        = string
  default     = "10.200.10.100"
}

variable "lb_pool_end" {
  description = "End of the LoadBalancer IP pool range"
  type        = string
  default     = "10.200.10.200"
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

# === Zot Registry Cache ===

variable "zot_cache_dir" {
  description = "Zot registry cache directory on the host"
  type        = string
  default     = "/var/tmp/atlas/zot-cache-data-test"
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

# === VM Resources ===

variable "cp_memory" {
  description = "Controlplane VM memory"
  type        = string
  default     = "2GiB"
}

variable "worker_memory" {
  description = "Worker VM memory"
  type        = string
  default     = "2GiB"
}

variable "vm_cpu" {
  description = "VM CPU count"
  type        = string
  default     = "2"
}

variable "vm_disk_size" {
  description = "VM disk size"
  type        = string
  default     = "10GiB"
}
