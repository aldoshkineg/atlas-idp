# IP topology
locals {
  cp_ips = length(var.cp_ips) > 0 ? var.cp_ips : [
    for i in range(var.controlplane_count) : "10.200.10.1${i + 1}"
  ]
  use_vip       = length(local.cp_ips) > 1 && var.cluster_vip != ""
  cp_endpoint   = "https://${local.use_vip ? var.cluster_vip : local.cp_ips[0]}:6443"
  kubelet_image = "ghcr.io/siderolabs/kubelet:${var.k8s_version}"
}

# Talos machine patches
locals {
  common_config_patches = [
    # mirrors с реальными endpoints — чтобы Talos включил config_path в containerd
    # machine.files ниже перезаписывает hosts.toml с server= (без fallback)
    <<-EOT
      machine:
        registries:
          mirrors:
            registry.k8s.io:
              endpoints:
                - http://${var.gateway}:5000
            quay.io:
              endpoints:
                - http://${var.gateway}:5000
            ghcr.io:
              endpoints:
                - http://${var.gateway}:5000
            docker.io:
              endpoints:
                - http://${var.gateway}:5000
            public.ecr.aws:
              endpoints:
                - http://${var.gateway}:5000
            gcr.io:
              endpoints:
                - http://${var.gateway}:5000
    EOT
    ,
    <<-EOT
      machine:
        files:
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/registry.k8s.io/hosts.toml
            op: overwrite
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/ghcr.io/hosts.toml
            op: overwrite
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/quay.io/hosts.toml
            op: overwrite
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/docker.io/hosts.toml
            op: overwrite
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/public.ecr.aws/hosts.toml
            op: overwrite
          - content: |
              server = "http://${var.gateway}:5000"

              [host."http://${var.gateway}:5000"]
                capabilities = ["pull", "resolve"]
            path: /etc/cri/conf.d/hosts/gcr.io/hosts.toml
            op: overwrite
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
          image: registry.k8s.io/kube-apiserver:${var.k8s_version}
        controllerManager:
          image: registry.k8s.io/kube-controller-manager:${var.k8s_version}
        scheduler:
          image: registry.k8s.io/kube-scheduler:${var.k8s_version}
    EOT
  ]

  cp_node_patches = [
    for i, ip in local.cp_ips : <<-EOT
      machine:
        install:
          disk: /dev/sda
        network:
          interfaces:
            - deviceSelector:
                busPath: "0*"
              addresses:
                - "${ip}/24"
              %{if local.use_vip && i == 0}
              vip:
                ip: ${var.cluster_vip}
              %{endif}
              routes:
                - network: "0.0.0.0/0"
                  gateway: "${var.gateway}"
        kubelet:
          image: ${local.kubelet_image}
          nodeIP:
            validSubnets:
              - "${var.cluster_cidr}"
    EOT
  ]

  worker_node_patches = [
    for ip in var.worker_ips : <<-EOT
      machine:
        install:
          disk: /dev/sda
        network:
          interfaces:
            - deviceSelector:
                busPath: "0*"
              addresses:
                - "${ip}/24"
              routes:
                - network: "0.0.0.0/0"
                  gateway: "${var.gateway}"
        kubelet:
          image: ${local.kubelet_image}
          nodeIP:
            validSubnets:
              - "${var.cluster_cidr}"
    EOT
  ]
}

# Cluster secrets
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Client configuration
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = concat(local.cp_ips, var.worker_ips)
  endpoints            = [local.use_vip ? var.cluster_vip : local.cp_ips[0]]
}

resource "local_sensitive_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${var.files_dir}/talosconfig"
}

# Machine configurations
data "talos_machine_configuration" "controlplane" {
  count            = length(local.cp_ips)
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cp_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = concat(local.common_config_patches, [
    local.cp_node_patches[count.index]
  ])
}

data "talos_machine_configuration" "worker" {
  count            = length(var.worker_ips)
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cp_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = concat(local.common_config_patches, [
    local.worker_node_patches[count.index]
  ])
}

# Debug config files
resource "local_sensitive_file" "cp_config_files" {
  for_each = { for i, ip in local.cp_ips : "cp-${i + 1}" => {
    config = data.talos_machine_configuration.controlplane[i].machine_configuration
  } }
  content  = each.value.config
  filename = "${var.files_dir}/${each.key}.yaml"
}

resource "local_sensitive_file" "worker_config_files" {
  for_each = { for i, ip in var.worker_ips : "worker-${i + 1}" => {
    config = data.talos_machine_configuration.worker[i].machine_configuration
  } }
  content  = each.value.config
  filename = "${var.files_dir}/${each.key}.yaml"
}

# Convenience lists for consumer modules
locals {
  cp_config_list     = [for c in data.talos_machine_configuration.controlplane : c.machine_configuration]
  worker_config_list = [for w in data.talos_machine_configuration.worker : w.machine_configuration]
}
