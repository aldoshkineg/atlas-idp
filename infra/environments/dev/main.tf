# Development environment configuration for kind cluster (using tehcyx/kind provider)

module "kind_cluster" {
  source = "../../modules/kind"

  cluster_name      = "dev-cluster"
  create_cluster    = true
  worker_node_count = 2

  # Enable ingress-ready labels for ingress controllers
  ingress_ready = true

  # Expose ports for ingress
  extra_port_mappings = [
    {
      container_port = 80
      host_port      = 80
      protocol       = "TCP"
    },
    {
      container_port = 443
      host_port      = 443
      protocol       = "TCP"
    }
  ]
}

# Корневой провайдер инициализируется строго во время apply, когда модуль готов
provider "kubernetes" {
  host                   = module.kind_cluster.endpoint
  cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
  client_certificate     = module.kind_cluster.client_certificate
  client_key             = module.kind_cluster.client_key
}

# Namespace создается без проблем, так как он ждет завершения модуля
resource "kubernetes_namespace" "example" {
  metadata {
    name = "example-app"
  }

  depends_on = [module.kind_cluster]
}

# Выводы (Outputs)
output "kubeconfig_path" {
  value     = module.kind_cluster.kubeconfig_path
  sensitive = true
}

output "cluster_ready" {
  value = module.kind_cluster.cluster_ready
}

output "cluster_name" {
  value = module.kind_cluster.cluster_name
}
