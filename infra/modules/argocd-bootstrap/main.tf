# Day-0 Argo CD bootstrap via Helm
# Creates namespace + deploys Argo CD Helm chart with minimal production-like configuration

# 1. Create ArgoCD namespace
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

# 2. Generate random admin password if not provided
resource "random_password" "argocd_admin" {
  count   = var.admin_password_bcrypt == "" ? 1 : 0
  length  = 16
  special = true
}

# 3. Deploy Argo CD via Helm
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = false # Already created above
  wait             = true
  timeout          = 600 # 10 minutes for initial install

  # Default values for local kind environment
  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }

      # Server configuration
      server = {
        service = {
          type = "NodePort"
          nodePortHttp = 30080
        }
        # Insecure mode for local dev (no TLS)
        extraArgs = var.insecure_mode ? ["--insecure"] : []
        
        # Resource limits for kind
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

      # Repo server configuration
      repoServer = {
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

      # Controller configuration
      controller = {
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # Application controller metrics
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

      # Notifications (disabled for minimal install)
      notifications = {
        enabled = false
      }

      # Dex (OAuth, disabled for local)
      dex = {
        enabled = false
      }

      # Redis HA (disabled for kind, using single redis)
      redis = {
        enabled = true
      }
      redis-ha = {
        enabled = false
      }

      # Configure repository credentials if repo_url provided
      configs = var.repo_url != "" ? {
        repositories = {
          "atlas-idp-repo" = {
            url  = var.repo_url
            type = var.repo_type
            name = "atlas-idp"
          }
        }
      } : {}
    })
  ]

  # Merge with custom values if provided
  values = var.argocd_values_override != "" ? [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      server = {
        service = {
          type = "NodePort"
          nodePortHttp = 30080
        }
        extraArgs = var.insecure_mode ? ["--insecure"] : []
      }
    }),
    var.argocd_values_override
  ] : [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      server = {
        service = {
          type = "NodePort"
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
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      controller = {
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
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
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd
  ]
}
