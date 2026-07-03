terraform {
  backend "local" {
    path = "/var/tmp/atlas/terraform/terraform.tfstate"
  }
}



# === Talos config generation (secrets, patches, machine configs) ===
module "talos_config" {
  source = "../../modules/talos-config"

  cluster_name       = var.cluster_name
  talos_version      = var.talos_version
  k8s_version        = var.k8s_version
  gateway            = var.gateway
  cluster_cidr       = var.cluster_cidr
  cp_ips             = var.cp_ips
  worker_ips         = var.worker_ips
  cluster_vip        = var.cluster_vip
  controlplane_count = var.controlplane_count
  files_dir          = var.files_dir
}

# === Zot registry cache ===
module "zot_cache" {
  source = "../../modules/zot-cache"

  enable   = true
  platform = "incus"

  container_name     = "zot-cache"
  port               = var.zot_port
  cache_dir          = var.zot_cache_dir
  incus_network      = "incusbr0"
  incus_proxy_listen = "tcp:${var.gateway}:5000"
  incus_image_alias  = "zot-cache"
  incus_image_ref    = var.zot_image_ref

  depends_on = [module.incus]
}

# === Incus VMs ===
module "incus" {
  source = "../../modules/incus"

  cluster_name         = var.cluster_name
  talos_image_file     = var.talos_image_path
  image_alias          = "talos-${replace(var.talos_version, "v", "")}-drbd"
  controlplane_configs = module.talos_config.cp_configs
  worker_configs       = module.talos_config.worker_configs
  cp_memory            = var.cp_memory
  worker_memory        = var.worker_memory
  cpu                  = var.vm_cpu
  disk_size            = var.vm_disk_size
}

# === Bootstrap: apply configs, bootstrap, get kubeconfig ===
module "talos_cluster" {
  source = "../../modules/talos-cluster"

  controlplane_configs = module.talos_config.cp_configs
  worker_configs       = module.talos_config.worker_configs
  client_configuration = module.talos_config.client_configuration
  cp_ips               = module.talos_config.cp_ips
  worker_ips           = module.talos_config.worker_ips
  files_dir            = var.files_dir

  depends_on = [module.incus, module.zot_cache]
}

# === Helm provider ===
# Uses a fixed path known at plan time (file created during talos_cluster apply)
provider "helm" {
  kubernetes {
    config_path = "${var.files_dir}/kubeconfig"
  }
}

# === Wait for API server before installing platform services ===
resource "null_resource" "wait_for_api" {
  depends_on = [module.talos_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 200); do
        if kubectl --kubeconfig ${module.talos_cluster.kubeconfig_path} get nodes >/dev/null 2>&1; then
          echo "API server is ready"
          exit 0
        fi
        echo "Waiting for API server... (attempt $${i}/36)"
        sleep 5
      done
      echo "API server not ready after 180s"
      exit 1
    EOT
  }
}

# === Cilium CNI ===
module "cilium" {
  source = "../../modules/cilium"

  depends_on = [null_resource.wait_for_api]

  cluster_name         = var.cluster_name
  cilium_chart_version = var.cilium_chart_version
  talos                = true

  cilium_settings = [
    { name = "hubble.enabled", value = "true", type = "auto" },
    { name = "gatewayAPI.enabled", value = "true", type = "auto" },
    { name = "bpf.hostLegacyRouting", value = "true", type = "auto" },
    { name = "l2announcements.enabled", value = "true", type = "auto" },
    { name = "l2announcements.leases.enabled", value = "true", type = "auto" },
  ]
}

# === Cilium LoadBalancer IP Pool ===
resource "null_resource" "cilium_lb_pool" {
  depends_on = [module.cilium, module.talos_cluster]

  triggers = {
    kubeconfig = module.talos_cluster.kubeconfig_path
    pool_spec  = <<-EOT
      apiVersion: cilium.io/v2
      kind: CiliumLoadBalancerIPPool
      metadata:
        name: default-pool
      spec:
        blocks:
          - start: ${var.lb_pool_start}
            stop: ${var.lb_pool_end}
    EOT
  }

  provisioner "local-exec" {
    command = <<-CMD
      kubectl --kubeconfig ${self.triggers["kubeconfig"]} apply -f - <<'MANIFEST'
      ${self.triggers["pool_spec"]}
      MANIFEST
    CMD
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-CMD
      kubectl --kubeconfig ${self.triggers["kubeconfig"]} delete --ignore-not-found ciliumloadbalancerippool default-pool
    CMD
  }
}

# === Outputs ===
output "cp_ips" {
  value = module.talos_config.cp_ips
}

output "worker_ips" {
  value = module.talos_config.worker_ips
}

output "talosconfig" {
  value = module.talos_config.talos_config_path
}

output "kubeconfig" {
  value = module.talos_cluster.kubeconfig_path
}
