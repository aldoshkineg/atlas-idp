# Kind Terraform Module

This module provides Terraform configuration for creating and managing a kind (Kubernetes IN Docker) cluster using the [tehcyx/kind](https://registry.terraform.io/providers/tehcyx/kind/latest) provider.

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) installed
- [Docker](https://www.docker.com/) running
- [Terraform](https://www.terraform.io/) >= 1.0
- Terraform provider `tehcyx/kind` version 0.7.0

## Usage

### Basic Usage

```hcl
module "kind_cluster" {
  source = "./infra/modules/kind"
  
  cluster_name = "my-cluster"
}
```

This will create a kind cluster with one control-plane node and one worker node.

### Advanced Usage with Custom Topology

```hcl
module "kind_cluster" {
  source = "./infra/modules/kind"
  
  cluster_name      = "my-cluster"
  worker_node_count = 2
  
  # Label control-plane for ingress
  ingress_ready = true
  
  # Expose ports
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
```

### Using with Kubernetes Provider

The module automatically configures the Kubernetes provider to connect to the created cluster via `~/.kube/config`:

```hcl
module "kind_cluster" {
  source = "./infra/modules/kind"
  cluster_name = "my-cluster"
}

# Deploy resources to the cluster
resource "kubernetes_namespace" "app" {
  metadata {
    name = "my-app"
  }
  
  depends_on = [module.kind_cluster]
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cluster_name | Name of the kind cluster | `string` | `"kind"` |
| create_cluster | Whether to create the kind cluster using Terraform | `bool` | `true` |
| worker_node_count | Number of worker nodes in the cluster | `number` | `1` |
| control_plane_nodes | List of control plane node configurations | `list(object)` | `[{role = "control-plane"}]` |
| ingress_ready | Whether to label the control-plane node as ingress-ready | `bool` | `false` |
| extra_port_mappings | Extra port mappings for the control-plane node | `list(object)` | `[]` |
| kubernetes_version | Kubernetes version to use (e.g., v1.27.0) | `string` | `""` |

### extra_port_mappings Object

```hcl
object({
  container_port = number
  host_port      = number
  protocol       = optional(string, "TCP")
})
```

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | Name of the kind cluster |
| kubeconfig_path | Path to the kubeconfig file (`~/.kube/config`) |
| cluster_ready | Indicates if the cluster is ready |
| cluster_endpoint | Kubernetes cluster endpoint |

## Example: Complete Development Setup

```hcl
module "kind_cluster" {
  source = "./infra/modules/kind"
  
  cluster_name      = "dev"
  worker_node_count = 2
  ingress_ready     = true
  
  extra_port_mappings = [
    { container_port = 80, host_port = 80 },
    { container_port = 443, host_port = 443 }
  ]
}

# Install NGINX Ingress Controller
resource "kubernetes_manifest" "nginx_ingress" {
  # ... ingress controller configuration
  
  depends_on = [module.kind_cluster]
}
```

## Notes

- Uses the `tehcyx/kind` Terraform provider (not shell commands)
- The kubeconfig is written to `~/.kube/config` by default
- When `create_cluster = false`, the module will try to connect to an existing kind cluster
- The cluster is automatically deleted when `terraform destroy` is run (only if `create_cluster = true`)
- Port mappings are useful for exposing ingress controllers or services running in the cluster
- The `ingress_ready` flag adds required labels for ingress controllers like NGINX

## Migration from Previous Version

If you were using the old version with `null_resource`, note that:
- The kubeconfig is now stored at `~/.kube/config` instead of the module directory
- Configuration is done via Terraform variables instead of a separate kind config file
- The provider handles cluster lifecycle (create/delete) automatically
