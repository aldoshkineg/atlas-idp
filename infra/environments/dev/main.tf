terraform {
  backend "local" {
    path = "/var/tmp/atlas/terraform/terraform.tfstate"
  }
}

variable "root_app_path" {
  description = "Path to the GitOps root Application manifest"
  type        = string
  default     = ""

  validation {
    condition     = var.root_app_path == "" || can(file(var.root_app_path))
    error_message = "root_app_path must point to an existing file or be empty to use the default path."
  }
}

# Kind API connection for providers
locals {
  kind_connection = {
    host                   = module.kind_cluster.endpoint
    cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
    client_certificate     = module.kind_cluster.client_certificate
    client_key             = module.kind_cluster.client_key
  }

  # Host port contracts for NodePort ingress (cilium)
  ports = {
    http  = 30081
    https = 30444
  }

  # Root Application manifest path
  root_app_path = var.root_app_path != "" ? var.root_app_path : "${path.root}/../../../gitops/bootstrap/root-app.yaml"

  # Control Zot registry cache
  enable_zot_cache = true
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
  enable_zot_cache = local.enable_zot_cache

  # Disable kindnet + kube-proxy for Cilium eBPF
  disable_default_cni = true

  # Expose ports for NodePort ingress (cilium)
  extra_port_mappings = [
    {
      container_port = local.ports.http
      host_port      = 80
      protocol       = "TCP"
    },
    {
      container_port = local.ports.https
      host_port      = 443
      protocol       = "TCP"
    },
  ]
}

# Zot registry cache (pull-through proxy for container images)
module "zot_cache" {
  source = "../../modules/zot-cache-docker"

  enable         = local.enable_zot_cache
  container_name = "kind-zot-registry"
  port           = 5000
  network_name   = "kind"
  cache_dir      = "/var/tmp/atlas/zot_cache/zot-cache-data"
  config_dir     = "/var/tmp/atlas"

  depends_on = [module.kind_cluster]
}

# Root Application manifest exists
check "root_app_manifest" {
  assert {
    condition     = fileexists(local.root_app_path)
    error_message = "root_app_path must point to an existing root Application manifest."
  }
}

# Providers: initialized after kind cluster is ready
provider "kubernetes" {
  host                   = local.kind_connection.host
  cluster_ca_certificate = local.kind_connection.cluster_ca_certificate
  client_certificate     = local.kind_connection.client_certificate
  client_key             = local.kind_connection.client_key
}

provider "helm" {
  kubernetes {
    host                   = local.kind_connection.host
    cluster_ca_certificate = local.kind_connection.cluster_ca_certificate
    client_certificate     = local.kind_connection.client_certificate
    client_key             = local.kind_connection.client_key
  }
}

# Cilium CNI (eBPF, replaces kindnet + kube-proxy)
module "cilium" {
  source = "../../modules/cilium"

  cilium_chart_version = "1.19.4"
  cluster_name         = module.kind_cluster.cluster_name

  depends_on = [module.kind_cluster]
}

module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace     = "argocd"
  argocd_chart_version = "7.7.5"
  # HTTP for local dev
  insecure_mode    = true
  create_namespace = true

  # Configure GitHub repository (replace with actual repo URL)
  repo_url  = "https://github.com/aldoshkineg/atlas-idp"
  repo_type = "git"

  depends_on = [
    module.kind_cluster,
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
        -n argocd --timeout=120s --kubeconfig=${module.kind_cluster.kubeconfig_path}

      kubectl apply -f ${local.root_app_path} \
        --kubeconfig=${module.kind_cluster.kubeconfig_path}
    EOT
  }

  depends_on = [module.argocd_bootstrap]
}
