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
      memory = "2Gi"
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
      cm = {
        "resource.customizations.health.batch_Job" = <<EOF
hs = {}
if obj.status ~= nil then
  if obj.status.succeeded ~= nil and obj.status.succeeded == 1 then
    hs.status = "Healthy"
    hs.message = "Job completed successfully"
    return hs
  end
end
hs.status = "Progressing"
hs.message = "Waiting for job to complete"
return hs
EOF
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
