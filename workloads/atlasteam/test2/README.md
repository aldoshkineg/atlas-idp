# test2

Managed by **atlasctl** — [Atlas IDP](https://github.com/aldoshkineg/atlas-idp) workload management CLI.

- **Group:** `atlasteam`
- **Namespace:** `atlasteam-test2`
- **Repository:** https://github.com/ealdoshkin/atlas-idp

## Directory structure

| Path           | Description                                                                                                                                                                                  |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app.yaml`     | ArgoCD Application definition                                                                                                                                                                |
| `infra/`       | Platform infrastructure resources: HTTPRoute + Certificate (gateway.yaml), NetworkPolicy, ResourceQuota. On `enable` — gateway.yaml goes to `gateway-routes/`, the rest goes to `resources/` |
| `secrets.yaml` | ExternalSecrets for DB, S3, Redis (synced to `resources/`)                                                                                                                                   |
| `monitoring/`  | PodMonitor + PrometheusRule (synced to `resources/`)                                                                                                                                         |
| `vault/`       | Vault policies and seed config (local, not synced)                                                                                                                                           |

## Commands

```bash
# Enable workload (create ArgoCD Application + gateway listener)
atlasctl enable atlasteam/test2

# Disable workload (remove from GitOps, keep directory)
atlasctl disable atlasteam/test2

# Delete workload directory (only after disable)
atlasctl delete atlasteam/test2
```
