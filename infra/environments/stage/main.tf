locals {
  cluster_name  = "talos-incus"
  cluster_vip   = "10.200.10.10"
  cp_endpoint   = "https://${local.cluster_vip}:6443"
  cp_ips        = ["10.200.10.11", "10.200.10.12", "10.200.10.13"]
  worker_ips    = ["10.200.10.20", "10.200.10.21"]
  talos_image   = "/var/tmp/atlas/incus/talos-drbd.qcow2"
  talos_version = "v1.11.2"
  gateway       = "10.200.10.1"
  cluster_cidr  = "10.200.10.0/24"
  lb_pool_start = "10.200.10.100"
  lb_pool_end   = "10.200.10.200"
}

# Generate cluster secrets (CA, service account keys, etc.)
resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

# Talos API client configuration (used by all talos provider resources below)
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = concat(local.cp_ips, local.worker_ips)
  endpoints            = [local.cluster_vip]
}

# Write talosconfig for talosctl
resource "local_sensitive_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${abspath(path.module)}/talos/talosconfig"
}

# Controlplane machine configurations (one per CP with unique IP)
data "talos_machine_configuration" "controlplane" {
  count            = length(local.cp_ips)
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cp_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version

  config_patches = concat([
    <<-EOT
      machine:
        install:
          disk: /dev/sda
        network:
          interfaces:
            - deviceSelector:
                busPath: "0*"
              addresses:
                - "${local.cp_ips[count.index]}/24"
              %{if count.index == 0}
              vip:
                ip: ${local.cluster_vip}
              %{endif}
              routes:
                - network: "0.0.0.0/0"
                  gateway: "${local.gateway}"
        kubelet:
          image: ghcr.io/siderolabs/kubelet:v1.34.1
          nodeIP:
            validSubnets:
              - "${local.cluster_cidr}"
    EOT
    ,
    <<-EOT
      cluster:
        proxy:
          disabled: true
        network:
          cni:
            name: "none"
        apiServer:
          image: registry.k8s.io/kube-apiserver:v1.34.1
        controllerManager:
          image: registry.k8s.io/kube-controller-manager:v1.34.1
        scheduler:
          image: registry.k8s.io/kube-scheduler:v1.34.1
    EOT
    ,
  ])
}

# Worker machine configurations (one per worker with unique IP)
data "talos_machine_configuration" "worker" {
  count            = length(local.worker_ips)
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cp_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version

  config_patches = [
    <<-EOT
      machine:
        install:
          disk: /dev/sda
        network:
          interfaces:
            - deviceSelector:
                busPath: "0*"
              addresses:
                - "${local.worker_ips[count.index]}/24"
              routes:
                - network: "0.0.0.0/0"
                  gateway: "${local.gateway}"
        kubelet:
          image: ghcr.io/siderolabs/kubelet:v1.34.1
          nodeIP:
            validSubnets:
              - "${local.cluster_cidr}"
    EOT
    ,
    <<-EOT
      cluster:
        proxy:
          disabled: true
        network:
          cni:
            name: "none"
        apiServer:
          image: registry.k8s.io/kube-apiserver:v1.34.1
        controllerManager:
          image: registry.k8s.io/kube-controller-manager:v1.34.1
        scheduler:
          image: registry.k8s.io/kube-scheduler:v1.34.1
    EOT
  ]
}

# Save generated configs to disk (useful for manual inspection / debug)
resource "local_sensitive_file" "controlplane_config" {
  for_each = {
    for i, ip in local.cp_ips : "cp-${i + 1}" => {
      config = data.talos_machine_configuration.controlplane[i].machine_configuration
      ip     = ip
    }
  }
  content  = each.value.config
  filename = "${abspath(path.module)}/talos/cp-${each.key}.yaml"
}

resource "local_sensitive_file" "worker_config_file" {
  for_each = {
    for i in range(length(local.worker_ips)) : "worker-${i + 1}" => {
      config = data.talos_machine_configuration.worker[i].machine_configuration
    }
  }
  content  = each.value.config
  filename = "${abspath(path.module)}/talos/${each.key}.yaml"
}

# Config lists for incus module
locals {
  cp_config_list = [for c in data.talos_machine_configuration.controlplane : c.machine_configuration]
  worker_config_list = [
    for w in data.talos_machine_configuration.worker : w.machine_configuration
  ]
}

# Phase 1: Incus infrastructure (bridge, profile, image, VMs)
module "incus" {
  source = "../../modules/incus"

  cluster_name         = local.cluster_name
  talos_image_file     = local.talos_image
  image_alias          = "talos-${replace(local.talos_version, "v", "")}-drbd"
  controlplane_configs = local.cp_config_list
  worker_configs       = local.worker_config_list
  cp_memory            = "2GiB"
  worker_memory        = "2GiB"
  cpu                  = "2"
  disk_size            = "10GiB"
}

# Phase 2-a: Apply config to all controlplane nodes
resource "talos_machine_configuration_apply" "controlplane" {
  count = length(local.cp_ips)

  depends_on = [module.incus]

  machine_configuration_input = data.talos_machine_configuration.controlplane[count.index].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  node                        = local.cp_ips[count.index]
  endpoint                    = local.cp_ips[count.index]
  apply_mode                  = "auto"
}

# Phase 2-b: Bootstrap the cluster (first CP only)
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ips[0]
  endpoint             = local.cp_ips[0]
}

# Phase 3: Get kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ips[0]
  endpoint             = local.cp_ips[0]
}

resource "local_sensitive_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${abspath(path.module)}/talos/kubeconfig"
}

# Phase 4: Apply worker configs (join them to cluster)
resource "talos_machine_configuration_apply" "worker" {
  count = length(local.worker_ips)

  depends_on = [talos_machine_bootstrap.this]

  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  node                        = local.worker_ips[count.index]
  endpoint                    = local.worker_ips[count.index]
  apply_mode                  = "no_reboot"
}

# Phase 5: Deploy Cilium CNI (kube-proxy replacement)
provider "helm" {
  kubernetes {
    config_path = local_sensitive_file.kubeconfig.filename
  }
}

module "cilium" {
  source = "../../modules/cilium"

  depends_on = [
    talos_machine_configuration_apply.worker,
    talos_cluster_kubeconfig.this,
  ]

  cluster_name         = local.cluster_name
  cilium_chart_version = "1.18.0"
  talos                = true

  cilium_settings = [
    { name = "hubble.enabled", value = "true", type = "auto" },
    { name = "gatewayAPI.enabled", value = "true", type = "auto" },
    { name = "bpf.hostLegacyRouting", value = "true", type = "auto" },
    { name = "l2announcements.enabled", value = "true", type = "auto" },
    { name = "l2announcements.leases.enabled", value = "true", type = "auto" },
  ]
}

resource "null_resource" "cilium_lb_pool" {
  depends_on = [module.cilium]

  triggers = {
    kubeconfig = local_sensitive_file.kubeconfig.filename
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
      kubectl --kubeconfig ${local_sensitive_file.kubeconfig.filename} apply -f - <<'MANIFEST'
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

output "cp_ips" {
  value = local.cp_ips
}

output "worker_ips" {
  value = local.worker_ips
}

output "talosconfig" {
  value = local_sensitive_file.talosconfig.filename
}

output "kubeconfig" {
  value = local_sensitive_file.kubeconfig.filename
}
