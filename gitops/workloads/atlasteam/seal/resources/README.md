# Seal

Managed by **atlasctl** — [Atlas IDP](https://github.com/aldoshkineg/atlas-idp) workload management CLI.

- **Group:** `atlasteam`
- **Namespace:** `atlasteam-seal`
- **Repository:** https://github.com/aldoshkineg/atlas-idp

## Commands

```bash
# Enable workload (create ArgoCD Application + gateway listener)
atlasctl enable atlasteam/seal

# Disable workload (remove from GitOps, keep directory)
atlasctl disable atlasteam/seal

# Delete workload directory (only after disable)
atlasctl delete atlasteam/seal
```
