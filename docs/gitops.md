# GitOps with Argo CD — Process & Structure

> Operational design of the Atlas IDP Argo CD deployment built around the
> **app-of-apps** pattern. This document captures the structure we converged
> on and the non-obvious rules we learned the hard way. Keep it in sync with
> `gitops/`.

## Idea

Argo CD manages the whole platform from a single **root application**
(`gitops/bootstrap/root-app.yaml`) that renders the directory
`gitops/platform/layers/`. That directory contains one **layer wrapper**
`Application` per platform layer plus the `AppProject` definitions.

Each layer is further split into its own directory
(`gitops/platform/<layer>/`) holding the leaf `Application`s (or raw
manifests) and their `values/`. This gives us an independent, reviewable
unit per concern (base, storage, security, observability, delivery,
workloads).

Two deliberate gates:

- **`root-app` is automated** — it owns creating the `AppProject`s and the
  layer wrappers, and keeps them in sync with git.
- **Layer wrappers are Manual** — `root-app` creates a wrapper CR but never
  syncs it. A layer is only deployed when an operator runs
  `argocd app sync <layer>`. This makes each layer a deliberate, gated action.

Inside a layer, the **leaf applications are `automated`**, so a single
`argocd app sync <layer>` cascades and deploys the entire layer as one unit
(see "Why leaf apps must be automated" below).

`base` is the exception: its wrapper _and_ its children are automated, so the
foundation (cert-manager, gateway-api, vault, linstor, external-secrets) comes
up hands-off as soon as `root-app` reconciles.

## Architecture

```
                         root-app  (project: default, AUTOMATED)
                         source: gitops/platform/layers
                                    │
            ┌───────────────┬────────┴─────────┬──────────────┬──────────────┐
            │               │                  │              │              │
        AppProjects    base (auto)        storage (Manual)  security       observability
        (wave -1000)   wave -100          wave -50         wave 0         wave 10
        base/sec/obs/                     │               wave 20        delivery
        storage/delivery/                 ├─ cnpg-operator  (auto)         wave 50
        workloads                         ├─ cnpg-barman-plugin (auto)      workloads
                           ┌──────────┐    ├─ snapshot-controller (auto)
                           │ base/    │    ├─ minio (auto)
                           │ children │    ├─ velero (auto)
                           │ (auto)   │    ├─ redis (auto)
                           └──────────┘    └─ postgres-cluster (auto)
```

## Repository structure

```
gitops/
├── bootstrap/
│   └── root-app.yaml                # multi-source root app (project: default)
└── platform/
    ├── layers/                      # what root-app renders
    │   ├── appprojects.yaml         # AppProject CRs (wave -1000)
    │   ├── base.yaml                # wrapper, automated,  wave -100, project: base
    │   ├── storage.yaml             # wrapper, Manual,     wave -50, project: storage
    │   ├── security.yaml            # wrapper, Manual,     wave 0,   project: security
    │   ├── observability.yaml       # wrapper, Manual,     wave 10,  project: observability
    │   ├── delivery.yaml            # wrapper, Manual,     wave 20,  project: delivery
    │   └── workloads.yaml           # wrapper, Manual,     wave 50,  project: workloads
    ├── base/          # leaf apps + resources/ + values/   (foundation)
    ├── storage/       # cnpg, redis, minio, velero, snapshot-controller + values/
    ├── security/      # cert-manager, vault, trivy, netpol + resources/
    ├── observability/ # prom-stack, loki, tempo, alloy, metrics-server
    │   └── resources/monitor/        # ServiceMonitor/PodMonitor for OTHER layers
    │       ├── redis-service-monitor.yaml
    │       └── postgres-pod-monitor.yaml
    ├── delivery/      # argo-rollouts, keda
    └── workloads/     # seal (external repo)
```

Each layer directory follows the same shape:

```
gitops/platform/<layer>/
├── <leaf-app>.yaml        # one Application per deployed component
├── resources/<app>/       # raw manifests when not a helm chart
└── values/<app>.yaml      # helm valueFiles referenced via $values
```

## AppProjects

Six per-layer `AppProject`s (`base`, `security`, `observability`, `storage`,
`delivery`, `workloads`) plus the built-in `platform` project. They are applied
first (sync-wave `-1000`) so every layer wrapper has a destination project to
live in. Each project whitelists only the namespaces/cluster-resources its
layer needs (tightening / Phase 2 still pending).

## Sync flow — deploying a layer

```
argocd app sync storage
        │
        ├─ root-app already created the `storage` wrapper CR (Manual, idle)
        ├─ sync creates the leaf Application CRs
        │     (cnpg-operator, redis, minio, velero, postgres-cluster, ...)
        └─ each leaf is automated → self-deploys its resources
```

Within a layer, leaf apps are ordered by `argocd.argoproj.io/sync-wave`
(operators first, then consumers) and gated by
`argocd.argoproj.io/depends-on` for cross-app dependencies.

### Sync waves (current)

| Wave  | Layer         | Notes                                  |
| ----- | ------------- | -------------------------------------- |
| -1000 | AppProjects   | created before any layer               |
| -100  | base          | automated foundation                   |
| -50   | storage       | Manual gate                            |
| 0     | security      | Manual gate                            |
| 10    | observability | Manual gate (provides prometheus CRDs) |
| 20    | delivery      | Manual gate                            |
| 50    | workloads     | Manual gate                            |

### depends-on / ordering

`depends-on` works across Applications in the `root-app` tree (proven: storage
leaf apps depend on `platform-secrets`/`linstor-cluster` from `base`). Use it
for both in-layer ordering and **layer-level** gating, e.g. the observability
wrapper can carry `depends-on: storage` so monitoring only deploys after the
data services are healthy.

The `platform-monitors` app (lives in `observability/resources/monitor/`)
carries `depends-on: kube-prometheus-stack` so the ServiceMonitor/PodMonitor
CRDs exist before the monitors are applied.

## Operating procedures

### Deploy a layer

```bash
argocd app sync <layer>      # e.g. storage, observability, security
```

Leaf apps are automated, so this single command deploys the whole layer.
Wait for health with `argocd app wait <layer> --health`.

### Delete a layer

```bash
argocd app delete <layer> --cascade
```

Cascades to the child Applications and prunes their resources (leaf apps have
`prune: true` + finalizers). **Namespaces are NOT auto-deleted** by Argo CD —
clean them up manually if desired (`kubectl delete ns <ns>`).

### Disable a layer (honest off-switch)

A Manual wrapper does **not** keep a layer off: `root-app` (automated) recreates
the wrapper CR from git on every reconcile, so after `argocd app delete` the
wrapper comes back (Manual/`OutOfSync`, children not deployed). To truly disable
a layer, move its **wrapper** into `gitops/platform/layers/disabled/` — `root-app`
renders that directory non-recursively, so the wrapper is ignored and not
recreated:

```bash
git mv gitops/platform/layers/<layer>.yaml gitops/platform/layers/disabled/   # off
git mv gitops/platform/layers/disabled/<layer>.yaml gitops/platform/layers/    # on
```

The layer's contents (`gitops/platform/<layer>/`) stay put — only the wrapper
moves, so re-enabling is trivial. Combine with a one-time
`argocd app delete <layer> --cascade` to also clear the running layer from the
cluster.

> `argocd app delete` has `--cascade`; `argocd app sync` does **not** (see
> below). So deleting a layer is one command, deploying it as a unit relies on
> leaf apps being automated.

### Add a new service to a layer

1. Drop a new leaf `Application` (or `resources/<app>/` manifests) into
   `gitops/platform/<layer>/`.
2. Set `project: <layer>`, `sync-wave`, and `depends-on` as needed.
3. `argocd app sync <layer>`.

## Lessons learned (read before touching sync config)

These are the non-obvious rules that bit us. They are about avoiding
**perpetual OutOfSync** in the app-of-apps tree.

### 1. Never declare `directory.recurse: false` explicitly

`recurse: false` is the Argo CD default. The cluster normalizes it to an empty
`directory: {}`, but git still declares it → the parent app sees a permanent
diff and reports the child `OutOfSync` (`serverside-applied` / `configured`)
forever. Only declare `recurse: true` when you actually need recursion (e.g. a
leaf app reading its own `resources/` subdir).

### 2. Use `group: "*"`, not `group: ""`, in `ignoreDifferences`

Empty group (`""`) is normalized away in the target manifest while the live CR
retains `group: ""`, causing the parent wrapper to drift. `group: "*"` is
semantically equivalent for core resources and is **not** normalized, so live
and target match. (Found in `redis.yaml` — three entries.)

### 3. `argocd app sync` has no `--cascade`

Unlike `argocd app delete`, the sync command cannot cascade into child
Applications in this Argo CD version. Therefore a parent sync only creates the
child CRs; the children deploy **only if they are `automated`**. This is why
leaf apps carry `automated` + `selfHeal`: it is the only way to make
`argocd app sync <layer>` deploy the entire layer as a unit.

### 4. Monitors live in the observability layer

`ServiceMonitor`/`PodMonitor` require the prometheus-operator CRDs, which are
installed by `kube-prometheus-stack` (observability). A storage component that
ships its own monitor therefore can't deploy until observability is up —
blocking the whole storage layer.

Rule: monitoring resources for a layer belong in
`observability/resources/monitor/`, deployed by the `platform-monitors` app
with `depends-on: kube-prometheus-stack`. This decouples storage (and any
other layer) from prometheus CRDs so they can deploy independently. KEDA is
unaffected — it scales from Redis directly, not via the ServiceMonitor.

### 5. Stale render cache after a failed/value change

When a sync fails (invalid task) or helm values change, Argo CD may keep
serving a stale rendered manifest, so a re-sync still shows the old resources.
Force a fresh render with:

```bash
argocd app get <app> --refresh
argocd app sync <app>
```

### 6. Manual wrappers are recreated by root-app

Deleting a layer (`argocd app delete <layer> --cascade`) removes it from the
cluster, but `root-app` (automated) will recreate the **wrapper CR** from git
on its next reconcile. The wrapper stays `Manual`/`OutOfSync` and does **not**
redeploy its children — so the layer does not come back on its own. To truly
retire a layer, move its wrapper into `gitops/platform/layers/disabled/` (see
"Disable a layer") instead of leaving it in `layers/`.

## Verification

```bash
argocd app list
argocd app get root-app
argocd app get <layer>          # Sync Status should be Synced, Health Healthy
```
