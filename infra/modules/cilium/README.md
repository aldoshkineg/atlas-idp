# Cilium Module

Terraform module for Cilium CNI installation via Helm. Replaces kindnet + kube-proxy with eBPF.

## Usage

```hcl
module "cilium" {
  source = "../../modules/cilium"

  cilium_chart_version = "1.19.4"
  cluster_name         = module.kind_cluster.cluster_name

  depends_on = [module.kind_cluster]
}
```

## Inputs

| Name                 | Description                                              | Type   | Default  | Required |
| -------------------- | -------------------------------------------------------- | ------ | -------- | -------- |
| cilium_chart_version | Cilium Helm chart version                                | string | "1.19.4" | no       |
| cluster_name         | Kind cluster name (for control-plane container hostname) | string | —        | yes      |

## Outputs

| Name             | Description                             |
| ---------------- | --------------------------------------- |
| cilium_installed | True if Cilium Helm release was created |
