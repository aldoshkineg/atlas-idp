# workloads/

User workload projects, managed by `atlasctl`.

- Each sub-directory is `<group>/<app>` (e.g. `atlasteam/seal`).
- This is the **single source of truth** for a workload. Edit manifests here.
- `atlasctl enable <group>/<app>` promotes the project into GitOps:
  - `app.yaml` → `gitops/workloads/<group>/<app>.yaml` (ArgoCD Application)
  - `infra/`, `monitoring/`, `secrets.yaml` → `gitops/workloads/<group>/<app>/resources/`
- Do **not** edit the generated files under `gitops/workloads/` by hand; re-run `atlasctl enable`.

Commands: `atlasctl new | seed | enable | disable | status | delete`.
