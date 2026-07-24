# Cilium Module

Terraform module for Cilium CNI installation via Helm. Replaces kube-proxy with eBPF.

## Usage

```hcl
module "cilium" {
  source = "../../modules/cilium"

  cilium_chart_version = "1.19.4"
  cluster_name         = module.talos_cluster.cluster_name

  depends_on = [module.talos_cluster]
}
```

## Inputs

| Name                 | Description                                              | Type   | Default  | Required |
| -------------------- | -------------------------------------------------------- | ------ | -------- | -------- |
| cilium_chart_version | Cilium Helm chart version                                | string | "1.19.4" | no       |
| cluster_name         | Cluster name (control-plane container hostname fallback) | string | —        | yes      |

## Outputs

| Name             | Description                             |
| ---------------- | --------------------------------------- |
| cilium_installed | True if Cilium Helm release was created |
