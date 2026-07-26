# recipes/

Standalone **cluster snippets** — manifests applied directly to the cluster with `kubectl`,
outside of the GitOps pipeline.

- These are operational helpers (backups, debugging, one-off configuration), not deployment state.
- Apply manually: `kubectl apply -f recipes/<name>` (or `kubectl apply -k recipes/<name>` for kustomizations).
- **Never reference `recipes/` from an ArgoCD Application** — it is documentation/snippets, not GitOps.

Current recipes:

- `cnpg-backup/` — CloudNativePG cluster with barman-cloud S3 backup (MinIO).
