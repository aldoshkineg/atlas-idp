# templates/

Golden-path templates used by the platform.

- `templates/gold/` holds the `atlasctl` scaffold source (`*.tmpl` files).
- `atlasctl new <group>/<app>` renders these into `workloads/<group>/<app>/`.
- **Edit here to change the shape of every new workload** (network-policy, resource-quota,
  pod-monitor, vault policy, secrets, ArgoCD Application template).

Do not place deployable manifests here — only templates consumed by `atlasctl`.
