locals {
  argocd_default_values = {
    global = {
      domain = "argocd.local"
    }

    server = {
      service = {
        type         = "NodePort"
        nodePortHttp = 30080
      }
      extraArgs = var.insecure_mode ? ["--insecure"] : []

      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "250m"
          memory = "256Mi"
        }
      }
    }

    repoServer = {
      resources = {
        limits = {
          cpu    = "500m"
          memory = "1500Mi"
        }
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
      }
    }

    controller = {
      resources = {
        limits = {
          cpu    = "1500m"
          memory = "1Gi"
        }
        requests = {
          cpu    = "750m"
          memory = "512Mi"
        }
      }
    }

    applicationSet = {
      enabled = true
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }

    notifications = {
      enabled = false
    }

    dex = {
      enabled = false
    }

    redis = {
      enabled = true
    }
    redis-ha = {
      enabled = false
    }

    configs = {
      params = {
        "reposerver.parallelism.limit" = "2"
      }
      repositories = var.repo_url != "" ? {
        "atlas-idp-repo" = {
          url   = var.repo_url
          type  = var.repo_type
          name  = "atlas-idp"
          depth = "1"
        }
      } : {}
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/component"  = "gitops"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "random_password" "argocd_admin" {
  count   = var.admin_password_bcrypt == "" ? 1 : 0
  length  = 16
  special = true
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = false
  wait             = true
  timeout          = 600

  values = concat(
    [yamlencode(local.argocd_default_values)],
    var.argocd_values_override != "" ? [var.argocd_values_override] : []
  )

  depends_on = [
    kubernetes_namespace.argocd
  ]
}
