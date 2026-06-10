# Development environment configuration for kind cluster (using tehcyx/kind provider)
terraform {
  backend "s3" {
    bucket                      = "atlas-tf-7612"
    key                         = "terraform/atlas-idp/terraform.tfstate"
    region                      = "eu-central-003"
    endpoints = {
      s3 = "https://s3.eu-central-003.backblazeb2.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

module "kind_cluster" {
  source = "../../modules/kind"

  cluster_name       = "atlas-idp"
  kubernetes_version = "v1.35.0"
  create_cluster     = true
  worker_node_count  = 2

  # Enable ingress-ready labels for ingress controllers
  ingress_ready = true

  # Enable zot mirror repos
  enable_cache = true

  # Expose ports for NodePort ingress (nginx-gateway-fabric)
  extra_port_mappings = [
    {
      container_port = 30081
      host_port      = 80
      protocol       = "TCP"
    },
    {
      container_port = 30444
      host_port      = 443
      protocol       = "TCP"
    }
  ]
}

# Providers: initialized after kind cluster is ready
provider "kubernetes" {
  host                   = module.kind_cluster.endpoint
  cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
  client_certificate     = module.kind_cluster.client_certificate
  client_key             = module.kind_cluster.client_key
}

provider "helm" {
  kubernetes {
    host                   = module.kind_cluster.endpoint
    cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
    client_certificate     = module.kind_cluster.client_certificate
    client_key             = module.kind_cluster.client_key
  }
}

# Day-0: Argo CD bootstrap via Helm
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace     = "argocd"
  argocd_chart_version = "7.7.5"
  insecure_mode        = true # HTTP for local dev
  create_namespace     = true

  # Configure GitHub repository (replace with actual repo URL)
  repo_url  = "https://github.com/aldoshkineg/atlas-idp"
  repo_type = "git"

  depends_on = [module.kind_cluster]
}

# Day-1: Apply root Application CR to kickstart GitOps
resource "null_resource" "argocd_root_app" {
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Argo CD server to be ready
      kubectl wait --for=condition=available deployment/argocd-server \
        -n argocd --timeout=120s --kubeconfig=${module.kind_cluster.kubeconfig_path}

      # Apply root Application
      kubectl apply -f ${path.root}/../../../gitops/bootstrap/root-app.yaml \
        --kubeconfig=${module.kind_cluster.kubeconfig_path}
    EOT
  }

  depends_on = [module.argocd_bootstrap]
}

# Example namespace for testing
resource "kubernetes_namespace" "check-ns" {
  metadata {
    name = "check-ns"
  }

  depends_on = [module.kind_cluster]
}

# Outputs
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

output "argocd_server_url" {
  description = "Argo CD server URL (NodePort)"
  value       = module.argocd_bootstrap.argocd_server_url
}

output "argocd_admin_password" {
  description = "Argo CD admin password"
  value       = module.argocd_bootstrap.argocd_admin_password
  sensitive   = true
}
