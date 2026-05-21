# 1. Создаем кластер KinD (БЕЗ каких-либо extra_mounts для hosts.toml)
resource "kind_cluster" "default" {
  count = var.create_cluster ? 1 : 0

  name            = var.cluster_name
  kubeconfig_path = pathexpand("~/.kube/kind")
  node_image      = var.kubernetes_version != "" ? "kindest/node:${var.kubernetes_version}" : null

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Патч, включающий поиск конфигураций в certs.d
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
    }

    # --- Worker ноды ---
    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"
      }
    }
  }

  # 2. Элегантная и надежная доставка конфигурации напрямую через Docker
  provisioner "local-exec" {
    command = <<-EOT
      if [ "${var.enable_cache}" = "true" ]; then
        echo "=== Настройка containerd зеркалирования ==="

        # Находим айдишники всех контейнеров нашего кластера через чистый Docker API
        for node in $(docker ps -q --filter name="${var.cluster_name}-"); do
          echo "Настраиваем ноду: $node"

          # Жестко сносим ложные папки, если Docker успел их там создать
          docker exec $node rm -rf /etc/containerd/certs.d/_default/hosts.toml

          # Создаем структуру директорий прямо внутри ноды
          docker exec $node mkdir -p /etc/containerd/certs.d/_default

          # Заливаем контент напрямую в файл внутри контейнера через стандартный поток ввода
          docker exec -i $node sh -c "cat > /etc/containerd/certs.d/_default/hosts.toml" << 'EOF'
server = "${var.cache_registry_server}"

[host."${var.cache_host_url}"]
  capabilities = ${jsonencode(var.cache_host_capabilities)}
EOF

          # Перезапускаем containerd внутри этой ноды
          docker exec $node systemctl restart containerd
          echo "Нода $node успешно настроена!"
        done
      fi
    EOT
  }
}
