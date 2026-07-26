# Workloads & GitOps pipeline

This document explains how application workloads move from a template to the cluster,
and how the repository directories relate to each other.

## Directory responsibilities

| Directory                                            | Role                                                                                                                               | Edited by              |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `templates/gold/`                                    | Golden-path **templates** (`.tmpl`) used by the platform to scaffold new workloads. Change here to affect every new workload.      | Platform team          |
| `workloads/<group>/<app>/`                           | **User projects** ready to be integrated via `atlasctl`. Single source of truth for a workload.                                    | App owner              |
| `gitops/workloads/<group>/<app>.yaml` + `resources/` | **Generated** Argo CD Application + synced resources, produced by `atlasctl enable`. DO NOT edit by hand.                          | `atlasctl` (generated) |
| `recipes/`                                           | **Cluster snippets** — standalone manifests applied directly with `kubectl` (backups, debugging). NOT part of the GitOps pipeline. | Anyone                 |

## Pipeline

```
templates/gold/             (golden templates, .tmpl)
   │  atlasctl new <group>/<app>
   ▼
workloads/<group>/<app>/    (user workspace — edit here)
   ├─ app.yaml              → ArgoCD Application template
   ├─ infra/ monitoring/ secrets.yaml
   └─ vault/                → k8s-auth-role, policy.hcl, seed-mapping.conf
   │  atlasctl enable
   ▼
gitops/workloads/<group>/<app>.yaml          (GENERATED from app.yaml)
gitops/workloads/<group>/<app>/resources/    (GENERATED from infra/, monitoring/, secrets.yaml)
   │  ArgoCD sync (automated, self-heal)
   ▼
cluster (namespace <group>-<app>)
```

## Commands

```bash
atlasctl new <group>/<app>     # scaffold from templates/gold into workloads/<group>/<app>
atlasctl seed <group>/<app>    # seed Vault secrets / ExternalSecrets mapping
atlasctl enable <group>/<app>  # generate the ArgoCD Application in gitops/workloads + sync
atlasctl disable <group>/<app> # remove from GitOps (keeps the workload dir)
atlasctl status <group>/<app>  # show sync/health
```

## Best practices

- **One source of truth.** Always edit under `workloads/`. The `gitops/workloads/.../resources`
  copy is generated; manual edits there are overwritten by the next `atlasctl enable`.
- **Keep `templates/gold` DRY.** New cross-cutting defaults (network-policy, resource-quota,
  pod-monitor, vault policy) belong in the golden templates, not copy-pasted per workload.
- **`recipes/` stays out of GitOps.** Anything in `recipes/` is applied manually with
  `kubectl apply -f recipes/<name>` and must never be referenced by an ArgoCD Application.
  It is operational documentation / snippets, not deployment state.
- **Per-workload Vault wiring** (`vault/k8s-auth-role.yaml`, `policy.hcl`, `seed-mapping.conf`)
  lives under `workloads/<group>/<app>/vault/` and is promoted by `atlasctl` — do not hand-apply.

## See also

- `templates/README.md`, `workloads/README.md`, `gitops/workloads/README.md`, `recipes/README.md`
- `docs/gitops.md` for the platform (non-workload) GitOps layers.
