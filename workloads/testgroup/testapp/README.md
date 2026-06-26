# testapp

Managed by **atlasctl** — [Atlas IDP](https://github.com/aldoshkineg/atlas-idp) workload management CLI.

- **Group:** `testgroup`
- **Namespace:** `testgroup-testapp`
- **Repository:** https://github.com/aldoshkineg/atlas-idp.git

## Directory structure

| Path           | Description                                                                                                                                                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app.yaml`     | ArgoCD Application definition                                                                                                                                                                                                 |
| `infra/`       | Platform infrastructure resources: HTTPRoute + Certificate (gateway.yaml), NetworkPolicy, CiliumNetworkPolicy, ResourceQuota, LimitRange. On `enable` — gateway.yaml goes to `gateway-routes/`, the rest goes to `resources/` |
| `secrets.yaml` | ExternalSecrets for DB, S3, Redis (synced to `resources/`)                                                                                                                                                                    |
| `monitoring/`  | PodMonitor + PrometheusRule (synced to `resources/`)                                                                                                                                                                          |
| `vault/`       | Vault policies and seed config (local, not synced)                                                                                                                                                                            |

## Commands

```bash
# Enable workload (create ArgoCD Application + gateway listener)
atlasctl enable testgroup/testapp

# Disable workload (remove from GitOps, keep directory)
atlasctl disable testgroup/testapp

# Delete workload directory (only after disable)
atlasctl delete testgroup/testapp
```
