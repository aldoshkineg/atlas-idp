# Day-0 Argo CD install (Helm). Ongoing config lives in gitops/bootstrap/.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}

variable "cluster_name" {
  type    = string
  default = "atlas-idp"
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

# Wire Helm release in environment root module (module.argocd_bootstrap).
