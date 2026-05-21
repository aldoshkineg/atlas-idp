# 1. Генерируем локальный файл (теперь он гарантированно создастся как файл, т.к. мы очистили раннер)
resource "local_file" "containerd_hosts" {
  filename = "${path.module}/hosts.toml"
  content  = <<-EOT
    server = "${var.cache_registry_server}"

    [host."${var.cache_host_url}"]
      capabilities = ${jsonencode(var.cache_host_capabilities)}
  EOT
}

# 2. Создаем кластер KinD (БЕЗ extra_mounts для hosts.toml)
resource "kind_cluster" "default" {
  count = var.create_cluster ? 1 : 0

  name            = var.cluster_name
  kubeconfig_path = pathexpand("~/.kube/kind")
  node_image      = var.kubernetes_version != "" ? "kindest/node:${var.kubernetes_version}" : null

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    containerd_config_patches = var.enable_cache ? [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      TOML
    ] : null

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
      # ЗДЕСЬ ПУСТО, НИКАКИХ extra_mounts ДЛЯ ФАЙЛА hosts.toml
    }

    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"
        # ЗДЕСЬ ТОЖЕ ПУСТО
      }
    }
  }
}

# 3. Безопасная доставка файла через Docker API
resource "null_resource" "inject_containerd_config" {
  count      = var.enable_cache && var.create_cluster ? 1 : 0
  depends_on = [kind_cluster.default]

  triggers = {
    config_hash = md5(local_file.containerd_hosts.content)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Injecting containerd hosts.toml into KinD nodes..."
      for node in $(kind get nodes --name ${var.cluster_name}); do
        # 1. На всякий случай зачищаем целевой путь внутри ноды, если там образовалась папка
        docker exec $node rm -rf /etc/containerd/certs.d/_default/hosts.toml

        # 2. Создаем родительскую директорию
        docker exec $node mkdir -p /etc/containerd/certs.d/_default

        # 3. Копируем файл напрямую через поток Docker API (это на 100% создаст файл)
        docker cp ${local_file.containerd_hosts.filename} $node:/etc/containerd/certs.d/_default/hosts.toml

        # 4. Перезапускаем containerd для применения изменений
        docker exec $node systemctl restart containerd
        echo "Successfully configured node: $node"
      done
    EOT
  }
}
