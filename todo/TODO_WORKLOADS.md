# Workloads — Golden Path Implementation

> **Legend:** `[x]` Done · `[ ]` Planned · `[~]` In Progress / Blocked

> **Architecture Decision:**
>
> - One shared CNPG `production-db` cluster for all workloads. Each project — its own DB
> - One shared Redis for the entire cluster
> - One shared MinIO for the entire cluster
> - Grafana — shared viewer account (not per-workload)

---

## Workload Structure

```
workloads/<group>/<app>/
├── app.yaml                    # ArgoCD Application → external repo (helm/source)
├── gateway.yaml                # (opt.) HTTPRoute + Certificate (---)
├── .secret-seed                # env vars template for atlasctl seed (gitignored)
├── vault/
│   ├── policy.hcl
│   ├── k8s-auth-role.yaml
│   └── seed-mapping.conf
├── secrets.yaml                # (opt.) ExternalSecrets: database + s3 + redis
├── infra/
│   ├── resource-quota.yaml     # (opt.)
│   └── network-policy.yaml     # (opt.)
├── monitoring/
│   ├── pod-monitor.yaml        # (opt.)
│   └── prometheus-rule.yaml    # (opt.)
├── autoscaling/
│   └── scaled-object.yaml      # (opt.) KEDA
└── rollouts/
    └── rollout.yaml            # (opt.) Argo Rollouts
```

**Features** determined by presence of directories/files:
`secrets.yaml`, `gateway.yaml`, `monitoring/`, `autoscaling/`, `rollouts/`

---

## Phase 1 — templates/gold/

**Goal:** Final composition of templates for `atlasctl new`.

```
templates/gold/
├── app.yaml.tmpl                    → workloads/<g>/<a>/app.yaml
├── gateway.yaml.tmpl                → workloads/<g>/<a>/gateway.yaml (opt.)
├── secrets.yaml.tmpl                → workloads/<g>/<a>/secrets.yaml (DB + S3 + Redis)
├── .secret-seed.tmpl                → workloads/<g>/<a>/.secret-seed
├── vault/
│   ├── policy.hcl.tmpl
│   ├── k8s-auth-role.yaml.tmpl
│   └── seed-mapping.conf.tmpl
├── monitoring/
│   ├── pod-monitor.yaml.tmpl
│   └── prometheus-rule.yaml.tmpl
└── infra/
    ├── resource-quota.yaml.tmpl
    └── network-policy.yaml.tmpl
```

- [x] **Created `secrets.yaml.tmpl`** — combines ExternalSecrets for production-db, MinIO, Redis
- [x] **Removed** `database/`, `s3/`, `redis/` — replaced by `secrets.yaml`
- [x] **Updated `vault/seed-mapping.conf.tmpl`** — default mappings for `db_*`, `s3_*`, `redis_*`

---

## atlasctl Commands

| Command                          | Description                                    | Flags                                                                                                        |
| -------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `atlasctl new <app> --group <g>` | Creates `workloads/<group>/<app>/` + templates | `--repo`, `--path`, `--helm`, `--db`, `--s3`, `--redis`, `--monitoring`, `--ingress`, `--keda`, `--rollouts` |
| `atlasctl seed <group>/<app>`    | Provisioning DB + bucket + Vault               | `--force` (skip validation), `--dry-run`                                                                     |
| `atlasctl enable <group>/<app>`  | Creates gitops Application + gateway listener  | `--sync`, `--push`, `--dry-run`, `--force`, `-y`                                                             |
| `atlasctl disable <group>/<app>` | Removes gitops Application + gateway listener  | `--sync`, `--push`, `--dry-run`, `--keep-workload`, `-y`                                                     |
| `atlasctl status <group>/<app>`  | Workload status                                | `--json`                                                                                                     |
| `atlasctl list`                  | List all workloads                             | `--json`                                                                                                     |

---

## Developer Workflow

```bash
# 1. Create workload
atlasctl new seal --group aldoshkineg --repo https://github.com/aldoshkineg/atlas-idp.git --db --s3 --ingress --monitoring

# 2. Configure app.yaml, gateway.yaml, .secret-seed (passwords already generated)

# 3. One-time: provision DB + bucket + Vault
atlasctl seed aldoshkineg/seal

# 4. Enable in GitOps
atlasctl enable aldoshkineg/seal --dry-run   # preview
atlasctl enable aldoshkineg/seal --sync --push  # apply

# 5. Status
atlasctl status aldoshkineg/seal

# 6. Disable (if needed)
atlasctl disable aldoshkineg/seal --dry-run
atlasctl disable aldoshkineg/seal --sync --push
```

---

## Phase 2 — `atlasctl new` ✓

**Goal:** Creates `workloads/<group>/<app>/` structure from templates.

- [x] Implement `cmd_new()`:
  - Creates `workloads/<group>/<app>/`
  - Copies templates from `templates/gold/` (selectively, by flags)
  - Creates `.secret-seed` with variables for DB/S3/Redis
  - `app.yaml` → `spec.source.repoURL`, `path`, `helm` from flags
  - `spec.destination.namespace` = `<group>-<app>` (or custom from `--namespace`)
  - Does not touch `gitops/`
- [x] **Update next steps** in `new` output
- [x] Verify that `atlasctl new seal --group aldoshkineg --repo ...` does not touch `gitops/`

---

## Phase 3 — `atlasctl seed <group>/<app>` ✓

**Goal:** Provisioning infrastructure and writing secrets to Vault.

- [x] Implement `cmd_seed()`:
  - Validation `.secret-seed` exists and is not empty
  - Validation of structure (app.yaml, vault/)
  - Reading `seed-mapping.conf` — which keys map where
- [x] **PostgreSQL Provisioning:**
  - Idempotent: CREATE DATABASE, CREATE USER / ALTER USER, GRANT
  - Via `kubectl exec production-db-1 -n database`
- [x] **MinIO Provisioning:**
  - Idempotent: create bucket, user, assign readwrite policy
  - Via `kubectl exec minio-0 -n minio -- mc ...`
- [x] **Redis:** Password read from platform secret `redis-auth` and written to Vault
- [x] **Write to Vault:** via `vault kv put` (locally or via `kubectl exec vault-0`)
- [x] Idempotency: DB/user/bucket checked before creation
- [x] `--dry-run`: show what will be created
- [x] `--force`: skip validation
- [ ] **Testing:** test on live cluster (Live Cluster Test)

---

## Phase 4 — `atlasctl enable <group>/<app>` ✓

**Goal:** Create ArgoCD Application CR + gateway listener.

- [x] Implement `cmd_enable()`:
  - Validation (if not `--force`): workload exists, app.yaml present, not already enabled
  - Reading namespace from `app.yaml`: `yq eval '.spec.destination.namespace'`
  - Reading hostname from `gateway.yaml`: `yq eval 'select(.kind == "HTTPRoute") | .spec.hostnames[0]'`
- [x] **Creates `gitops/workloads/<group>/<app>.yaml`:** single Application with `recurse: true`, depends-on, sync-wave 90
- [x] **Patch gateway listener** (if `gateway.yaml` exists) via `yq eval -i`
- [x] Idempotency: listener not duplicated
- [x] `--dry-run`: show file contents
- [x] `--sync`: git add + git commit
- [x] `--push`: git push

---

## Phase 5 — `atlasctl disable <group>/<app>` ✓

**Goal:** Remove workload from GitOps.

- [x] Implement `cmd_disable()`:

  - **Order:**
    1. First remove listener from gateway (otherwise ArgoCD will recreate the app)
    2. Then remove Application CRs
  - Reading hostname from `gateway.yaml` (if present):

    ```bash
    yq -i 'del(.spec.listeners[] | select(.name == "https-'"$APP"'"))' \
      gitops/platform/layers/networking/values/gateway-resources/gateway.yaml
    ```

- [ ] Removes:
  - `gitops/workloads/<group>/<app>.yaml`
  - If `<group>/` directory is empty — removes it too
- [ ] Flags:
  - `--sync`: `git add -A gitops/workloads/<group>/` + `git add gitops/platform/layers/networking/values/gateway-resources/gateway.yaml` + `git commit -m "disable(workloads): remove {{GROUP}}/{{APP}}"`
  - `--push`: `git push`
  - `--dry-run`: show which files will be removed
  - `--keep-workload`: don't touch `workloads/<group>/<app>/`
  - `-y`: no confirmation

---

## Phase 6 — `atlasctl status <group>/<app>` ✓

- [x] Implement `cmd_status()`:
  - Fields: name, namespace, features, enabled, gateway-listener, argocd-sync
  - `--json`: JSON output

---

## Phase 7 — `atlasctl list` ✓

- [x] Implement `cmd_list()`:
  - Scans `workloads/` for `app.yaml`
  - For each: group, app, features, enabled status, gateway listener
  - `--json`: JSON output, colored output (`✓` — enabled, `○` — disabled)

---

## Phase 8 — Seal Integration

**Goal:** Migrate Seal to new workflow.

- [ ] Migrate `workloads/aldoshkineg/seal/`:
  - Remove `database/cluster.yaml`, `database/objectstore.yaml`, `database/scheduled-backup.yaml`, `database/pod-monitor.yaml`
  - Remove `database/external-secret.yaml`, `s3/external-secret.yaml` (if present)
  - Create `secrets.yaml` — single file DB + S3 + Redis
  - Remove old `gitops/workloads/layers/aldoshkineg/` (entire directory)
  - Create fresh `app.yaml` per new template
  - Run `atlasctl enable` to create `gitops/workloads/aldoshkineg/seal.yaml`
- [ ] `atlasctl seed aldoshkineg/seal` → exit 0:
  - Created DB `sealdb` in production-db
  - Created bucket `workloads/aldoshkineg/seal` in MinIO
  - All credentials written to Vault
- [ ] `atlasctl enable aldoshkineg/seal -y --sync --push`:
  - Created `gitops/workloads/aldoshkineg/seal.yaml`
  - Added listener `https-seal` in gateway.yaml
  - ArgoCD synced the Application
- [ ] `atlasctl status aldoshkineg/seal` →:
  - `enabled: true`
  - `features: [secrets, monitoring, gateway]`
  - `gateway-listener: true`
- [ ] `atlasctl disable aldoshkineg/seal -y`:
  - Removed listener `https-seal` from gateway
  - Removed `seal.yaml` from gitops
- [ ] `atlasctl enable aldoshkineg/seal -y --sync --push` (re-enable):
  - listener restored
  - Application restored
- [ ] `atlasctl list` → shows `aldoshkineg/seal` with features and status

---

## Phase 9 — Root-app update ✓

- [x] Update `gitops/bootstrap/root-app.yaml`:
  - Source 2: `path: gitops/workloads/layers` → `path: gitops/workloads`
  - `exclude: "README.md"` → `exclude: "{README.md,.gitkeep}"`
- [ ] Verify that root-app syncs Applications from `gitops/workloads/` (live cluster test)

---

## Phase 10 — Makefile + Documentation

- [ ] Add Makefile targets:

  ```makefile
  atlasctl-new:    tools/atlasctl/atlasctl.sh new $(ARGS)
  atlasctl-seed:   tools/atlasctl/atlasctl.sh seed $(ARGS)
  atlasctl-enable: tools/atlasctl/atlasctl.sh enable $(ARGS)
  atlasctl-disable:tools/atlasctl/atlasctl.sh disable $(ARGS)
  atlasctl-status: tools/atlasctl/atlasctl.sh status $(ARGS)
  atlasctl-list:   tools/atlasctl/atlasctl.sh list $(ARGS)
  ```

- [ ] Update `apps/README.md`:
  - Document full workflow (new → seed → enable → disable)
  - Describe workload directory structure
  - Mention `.secret-seed` (gitignored)
  - Remove mention of manual commit
  - Add section Infrastructure Components
  - Add section Argo Rollouts Integration

---

## Phase 11 — Pre-commit & Validation

- [ ] `yamllint` on all new YAML files
- [ ] `shellcheck` on `tools/atlasctl/atlasctl.sh`
- [ ] `trivy` on templates (should have no false positives on `{{}}`)
- [ ] `pre-commit run --all-files` — all hooks pass
