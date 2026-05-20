terraform {
  required_version = ">= 1.5.0"
}

terraform {
  backend "local" {
    path = ".terraform/terraform.tfstate"
  }
}

module "cluster" {
  source = "../../modules/cluster"

  cluster_name = var.cluster_name
}

module "argocd_bootstrap" {
  source = "../../bootstrap/argocd"

  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  depends_on = [module.cluster]
}
