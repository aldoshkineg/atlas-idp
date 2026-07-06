terraform {
  backend "local" {
    path = "/var/tmp/atlas/terraform/terraform.tfstate"
  }
}

# === Derived locals ===
locals {
  worker_ips    = length(var.worker_ips) > 0 ? var.worker_ips : [for i in range(var.worker_count) : cidrhost(var.cluster_cidr, 20 + i)]
  lb_pool_start = var.lb_pool_start != "" ? var.lb_pool_start : cidrhost(var.cluster_cidr, 100)
  lb_pool_end   = var.lb_pool_end != "" ? var.lb_pool_end : cidrhost(var.cluster_cidr, 200)

  # Root Application manifest path
  root_app_path = var.root_app_path != "" ? var.root_app_path : "${path.root}/../../../gitops/bootstrap/root-app.yaml"

  # K8s connection config shared between helm and kubernetes providers
  k8s_connection = {
    host                   = module.talos_cluster.kubernetes_client_config.host
    cluster_ca_certificate = base64decode(module.talos_cluster.kubernetes_client_config.ca_certificate)
    client_certificate     = base64decode(module.talos_cluster.kubernetes_client_config.client_certificate)
    client_key             = base64decode(module.talos_cluster.kubernetes_client_config.client_key)
  }
}


# === Talos config generation (secrets, patches, machine configs) ===
module "talos_config" {
  source = "../../modules/talos-config"

  cluster_name       = var.cluster_name
  talos_version      = var.talos_version
  k8s_version        = var.k8s_version
  zot_address        = var.zot_address
  cluster_cidr       = var.cluster_cidr
  cp_ips             = var.cp_ips
  worker_ips         = local.worker_ips
  cluster_vip        = var.cluster_vip
  controlplane_count = var.controlplane_count
  files_dir          = var.files_dir
  pause_image        = var.pause_image
  skip_fallback      = var.skip_fallback
}

# === Zot registry cache ===
module "zot_cache" {
  source = "../../modules/zot-cache"

  enable      = var.zot_enable
  port        = var.zot_port
  cache_dir   = var.zot_cache_dir
  network     = module.incus.bridge_name
  gateway     = var.gateway
  image_alias = "zot-cache"
  image_ref   = var.zot_image_ref
  static_ip   = var.zot_address
}

# === Incus VMs ===
module "incus" {
  source = "../../modules/incus"

  bridge_subnet        = "${var.gateway}/${split("/", var.cluster_cidr)[1]}"
  cluster_name         = var.cluster_name
  talos_image_file     = var.talos_image_path
  talos_image_url      = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/ncloud-amd64.qcow2"
  image_alias          = "talos-${replace(var.talos_version, "v", "")}-drbd"
  controlplane_configs = module.talos_config.cp_configs
  worker_configs       = module.talos_config.worker_configs
  cp_memory            = var.cp_memory
  worker_memory        = var.worker_memory
  cpu                  = var.vm_cpu
  disk_size            = var.vm_disk_size
  extra_disk_size      = var.worker_extra_disk
  extra_pool_size      = var.extra_pool_size
  seed_iso_dir         = var.seed_iso_dir
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
# Uses inline k8s config from talos_cluster output (known after apply → defers until apply)
provider "helm" {
  kubernetes {
    host                   = local.k8s_connection.host
    cluster_ca_certificate = local.k8s_connection.cluster_ca_certificate
    client_certificate     = local.k8s_connection.client_certificate
    client_key             = local.k8s_connection.client_key
  }
}

# === Cilium CNI ===
module "cilium" {
  source = "../../modules/cilium"

  depends_on = [module.talos_cluster]

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
# TODO: move to Argo CD (network config) as CiliumLoadBalancerIPPool manifest
resource "null_resource" "cilium_lb_pool" {
  depends_on = [module.cilium]

  triggers = {
    kubeconfig = module.talos_cluster.kubeconfig_path
    pool_spec  = <<-EOT
      apiVersion: cilium.io/v2
      kind: CiliumLoadBalancerIPPool
      metadata:
        name: default-pool
      spec:
        blocks:
          - start: ${local.lb_pool_start}
            stop: ${local.lb_pool_end}
    EOT
  }

  provisioner "local-exec" {
    command = <<-CMD
      until kubectl --kubeconfig ${self.triggers["kubeconfig"]} get crd ciliumloadbalancerippools.cilium.io >/dev/null 2>&1; do
        echo "Waiting for Cilium CRD..."
        sleep 5
      done
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

# Kubernetes provider (uses Talos cluster kubeconfig)
provider "kubernetes" {
  host                   = local.k8s_connection.host
  cluster_ca_certificate = local.k8s_connection.cluster_ca_certificate
  client_certificate     = local.k8s_connection.client_certificate
  client_key             = local.k8s_connection.client_key
}

# Root Application manifest exists
check "root_app_manifest" {
  assert {
    condition     = fileexists(local.root_app_path)
    error_message = "root_app_path must point to an existing root Application manifest."
  }
}

# Argo CD bootstrap
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace     = "argocd"
  argocd_chart_version = "7.7.5"
  insecure_mode        = true
  create_namespace     = true

  repo_url  = "https://github.com/aldoshkineg/atlas-idp"
  repo_type = "git"

  depends_on = [
    module.cilium
  ]
}

# Bootstrap root app once; Argo CD owns it after apply
resource "null_resource" "argocd_root_app" {
  triggers = {
    root_app_sha1 = filesha1(local.root_app_path)
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl wait --for=condition=available deployment/argocd-server \
        -n argocd --timeout=120s --kubeconfig=${module.talos_cluster.kubeconfig_path}

      kubectl apply -f ${local.root_app_path} \
        --kubeconfig=${module.talos_cluster.kubeconfig_path}
    EOT
  }

  depends_on = [module.argocd_bootstrap]
}
