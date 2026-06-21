# Argo CD Helm defaults
locals {
  argocd_server_resources = {
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
    requests = {
      cpu    = "250m"
      memory = "256Mi"
    }
  }

  argocd_repo_server_resources = {
    limits = {
      cpu    = "500m"
      memory = "1500Mi"
    }
    requests = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }

  argocd_controller_resources = {
    limits = {
      cpu    = "1500m"
      memory = "1Gi"
    }
    requests = {
      cpu    = "750m"
      memory = "512Mi"
    }
  }

  argocd_application_set_resources = {
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
  }

  argocd_default_values = {
    global = {
      domain = "argocd.local"
    }

    server = {
      service = {
        type = "ClusterIP"
      }
      extraArgs = var.insecure_mode ? ["--insecure"] : []
      resources = local.argocd_server_resources
    }

    repoServer = {
      resources = local.argocd_repo_server_resources
    }

    controller = {
      resources = local.argocd_controller_resources
    }

    applicationSet = {
      enabled   = true
      resources = local.argocd_application_set_resources
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
    "redis-ha" = {
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
      cm = {
        "resource.customizations.health.external-secrets.io_ExternalSecret" = <<-EOT
          hs = {}
          if obj.status ~= nil and obj.status.conditions ~= nil then
            for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "Ready" then
                if condition.status == "True" then
                  hs.status = "Healthy"
                  hs.message = condition.message or "synced"
                elseif condition.status == "False" then
                  hs.status = "Degraded"
                  hs.message = condition.message or "sync error"
                else
                  hs.status = "Progressing"
                  hs.message = condition.message or "unknown"
                end
                return hs
              end
            end
          end
          hs.status = "Progressing"
          hs.message = "waiting for sync"
          return hs
        EOT
      }
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
