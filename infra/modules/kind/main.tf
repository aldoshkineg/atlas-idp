# Create kind cluster using the kind provider
resource "kind_cluster" "default" {
  count = var.create_cluster ? 1 : 0

  name            = var.cluster_name
  kubeconfig_path = pathexpand("~/.kube/kind")

  # Configure cluster topology
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # СТАНДАРТНЫЙ ИНСТАЛЛ: Ровно один Control Plane (без всяких dynamic-циклов)
    node {
      role = "control-plane"

      # Передаем патч для Ingress напрямую согласно документации провайдера
      kubeadm_config_patches = var.ingress_ready ? [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ] : []

      # Проброс портов для Ingress (остается динамическим)
      dynamic "extra_port_mappings" {
        for_each = var.extra_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = lookup(extra_port_mappings.value, "protocol", "TCP")
        }
      }
    }

    # Worker nodes: Создает столько нод, сколько указано в var.worker_node_count
    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"
      }
    }
  }
}
