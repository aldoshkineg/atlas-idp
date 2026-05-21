# 1. Автоматически генерируем локальный файл hosts.toml
resource "local_file" "containerd_hosts" {
  filename = "${path.module}/hosts.toml"
  content  = <<-EOT
    server = "${var.cache_registry_server}"

    [host."${var.cache_host_url}"]
      capabilities = ${jsonencode(var.cache_host_capabilities)}
  EOT
}

# 2. Создаем кластер KinD через нативный блок конфигурации
resource "kind_cluster" "default" {
  count = var.create_cluster ? 1 : 0

  name            = var.cluster_name
  kubeconfig_path = pathexpand("~/.kube/kind")
  node_image      = var.kubernetes_version != "" ? "kindest/node:${var.kubernetes_version}" : null

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Включаем поддержку директории certs.d только если кэш активен
    containerd_config_patches = var.enable_cache ? [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      TOML
    ] : null

    # --- Control-plane нода ---
    node {
      role = "control-plane"

      kubeadm_config_patches = var.ingress_ready ? [
        <<-EOF
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOF
      ] : null

      dynamic "extra_port_mappings" {
        for_each = var.extra_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = upper(extra_port_mappings.value.protocol)
        }
      }

      # Твой родной рабочий маут, который активируется только при var.enable_cache = true
      dynamic "extra_mounts" {
        for_each = var.enable_cache ? [1] : []
        content {
          host_path      = abspath(local_file.containerd_hosts.filename)
          container_path = "/etc/containerd/certs.d/_default/hosts.toml"
          read_only      = true
        }
      }
    }

    # --- Worker ноды ---
    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"

        # Динамически монтируем hosts.toml в каждую worker ноду, если кэш включен
        dynamic "extra_mounts" {
          for_each = var.enable_cache ? [1] : []
          content {
            host_path      = abspath(local_file.containerd_hosts.filename)
            container_path = "/etc/containerd/certs.d/_default/hosts.toml"
            read_only      = true
          }
        }
      }
    }
  }
}
