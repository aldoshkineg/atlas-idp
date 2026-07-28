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

## atlasctl — the developer CLI

`atlasctl` (Go, Cobra) is the self-service interface of the platform. Full command
reference, flags and architecture: [`tools/atlasctl/README.md`](../tools/atlasctl/README.md).

```bash
atlasctl new <group>/<app>     # scaffold from templates/gold into workloads/<group>/<app>
atlasctl seed <group>/<app>    # provision Postgres db/user + MinIO bucket, write creds to Vault
atlasctl enable <group>/<app>  # generate the ArgoCD Application in gitops/workloads,
                               # sync resources/, add the gateway listener + route
atlasctl disable <group>/<app> # remove from GitOps (keeps the workload dir)
atlasctl status <group>/<app>  # features / enabled / ArgoCD sync (--json)
atlasctl list                  # all workloads
atlasctl logs | backup         # day-2 helpers
```

What `new` scaffolds (all from `templates/gold/`, no per-feature flags): the ArgoCD
`app.yaml`, `secrets.yaml` (ExternalSecrets), `vault/` (policy, k8s-auth role, seed
mapping), `monitoring/` (PodMonitor, PrometheusRule) and `infra/` (gateway route,
NetworkPolicy + CCNP, KEDA ScaledObject, ResourceQuota, LimitRange).

`seed` reads the git-ignored `.secret-seed` + `vault/seed-mapping.conf` and writes
credentials to Vault under `secret/workloads/<group>/<app>/` — the same ESO flow as
platform secrets ([`vault.md`](vault.md)).

Build & dev loop: `make atlasctl-build`, `make atlasctl-test`, `make atlasctl-vet`;
binary at `tools/atlasctl/bin/atlasctl`.

## Reference workload: seal

`seal` is the multi-service reference app that exercises every platform capability:
REST API + Redis-driven worker (PDF signing) + HTMX UI, Postgres (CNPG), MinIO output
bucket, KEDA scaling, Argo Rollouts canary, Vault-backed secrets, full
metrics/logs/traces wiring.

- App code, local dev (`docker compose`, Taskfile), architecture:
  [`apps/seal/README.md`](../apps/seal/README.md) and `apps/seal/doc/`.
- Deployed instance: `gitops/workloads/atlasteam/seal.yaml` (Helm chart
  `apps/seal/charts/seal` + generated `resources/`), namespace `atlasteam-seal`,
  exposed at `https://seal.atlas`.
- Make targets: `seal-build`, `seal-push`, `seal-unit`, `seal-verify` (cosign),
  `seal-dc-up|down|logs`, e2e `make test-seal`.

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

- [`tools/atlasctl/README.md`](../tools/atlasctl/README.md) — full CLI reference
- [`apps/seal/README.md`](../apps/seal/README.md) — reference workload internals
- `templates/README.md`, `workloads/README.md`, `gitops/workloads/README.md`, `recipes/README.md`
- `docs/gitops.md` for the platform (non-workload) GitOps layers.
