# Argo CD Bootstrap Module

Terraform module for Day-0 Argo CD installation via Helm chart.

## Purpose

This module handles the initial deployment of Argo CD into a Kubernetes cluster. After this bootstrap:

1. Terraform creates the namespace and deploys Argo CD Helm chart
2. A root Application CR is applied (either via Terraform or post-apply script)
3. Argo CD takes over and manages all subsequent platform/workload deployments via GitOps

## Features

- Creates `argocd` namespace with proper labels
- Deploys Argo CD Helm chart from official argo-helm repository
- Configures NodePort service for local kind access (port 30080)
- Insecure mode for local development (HTTP, no TLS)
- Resource limits tuned for kind cluster
- Optional custom values override
- Optional repository credential configuration

## Usage

```hcl
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace      = "argocd"
  argocd_chart_version  = "7.7.5"
  insecure_mode         = true
  repo_url              = "https://github.com/your-org/atlas-idp"
  create_namespace      = true
}
```

## Inputs

| Name                  | Description               | Type   | Default  | Required |
| --------------------- | ------------------------- | ------ | -------- | -------- |
| argocd_namespace      | Namespace for Argo CD     | string | "argocd" | no       |
| argocd_chart_version  | Helm chart version        | string | "7.7.5"  | no       |
| insecure_mode         | Run in HTTP mode (no TLS) | bool   | true     | no       |
| repo_url              | GitHub repo URL           | string | ""       | no       |
| repo_type             | Repository type           | string | "git"    | no       |
| create_namespace      | Create namespace          | bool   | true     | no       |
| admin_password_bcrypt | Admin password hash       | string | ""       | no       |

## Outputs

| Name                  | Description                |
| --------------------- | -------------------------- |
| argocd_namespace      | Deployed namespace         |
| argocd_server_url     | Server URL (NodePort)      |
| argocd_admin_password | Admin password (sensitive) |
| helm_release_status   | Helm release status        |

## Post-Bootstrap

After this module completes, apply the root Application:

```bash
kubectl apply -f gitops/bootstrap/root-app.yaml
```

This kicks off the GitOps cascade: root-app → platform apps → workload apps.

## Day-1+ Self-Management

Once Argo CD is running, you can optionally create an Application CR that manages Argo CD itself:
`gitops/bootstrap/argocd/argocd-app.yaml` → points to the same Helm chart, ensuring Argo CD self-heals.
