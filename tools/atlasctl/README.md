# atlasctl — Workload Management CLI (Go Port)

Manages the full lifecycle of platform workloads in Atlas IDP — from scaffolding to GitOps promotion.

> **Status**: Bash implementation (legacy) in `atlasctl.sh` → migrating to Go binary.
> The bash version at `tools/atlasctl/atlasctl.sh` remains the active CLI until the Go rewrite is complete.
> See `TODO.md` Phase 9 for the migration roadmap and current progress.

## Development (Go Build)

```bash
# Build from source (from repo root)
go build -o tools/atlasctl/bin/atlasctl ./tools/atlasctl/

# Or via Task
go-task -t tools/atlasctl/Taskfile.yml build

# Run
./tools/atlasctl/bin/atlasctl --help
```

### Dependencies

- Go 1.23+
- Running `atlas-idp` kind cluster (for `seed`, `enable`, `status`)
- Access to Vault (via k8s or direct API)
- Access to CNPG database (via k8s pod exec for `seed`)

## Commands

| Command   | Description                                               |
| --------- | --------------------------------------------------------- |
| `new`     | Scaffold workload structure from golden path templates    |
| `seed`    | Provision DB + S3 bucket + write secrets to Vault         |
| `enable`  | Promote workload to GitOps (ArgoCD Application + gateway) |
| `disable` | Remove workload from GitOps                               |
| `delete`  | Delete workload directory (only if disabled)              |
| `status`  | Show workload status (features, enabled, ArgoCD sync)     |
| `list`    | List all registered workloads                             |

---

## `atlasctl new`

Creates `workloads/<group>/<app>/` with all golden path manifests.

```bash
# Minimal
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git

# With Helm chart
atlasctl new myapp --group team-a --repo https://github.com/team-a/myapp.git \
  --repo-path charts/myapp --helm

# With Helm values file
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp.git \
  --repo-path charts/seal --helm --helm-values ./seal-values.yaml
```

### Flags

| Flag                | Description                                        |
| ------------------- | -------------------------------------------------- |
| `--group <g>`       | Team/group name                                    |
| `--repo <url>`      | Application repository URL                         |
| `--namespace <ns>`  | Kubernetes namespace (default: `<group>-<app>`)    |
| `--repo-path <p>`   | Path to manifests within repo (default: `.`)       |
| `--helm`            | Use Helm chart                                     |
| `--helm-values <s>` | Inline Helm values string or file path             |
| `--sa <sas>`        | Service accounts for Vault auth (default: `<app>`) |
| `-y` / `--yes`      | Skip confirmation prompt                           |

> All manifests are generated unconditionally: gateway.yaml (HTTPRoute + Certificate), secrets.yaml (ExternalSecrets), vault/, monitoring/, infra/ (NetworkPolicy + ResourceQuota). No per-feature flags are required.

### Output Structure

```
workloads/<group>/<app>/
├── app.yaml               # ArgoCD Application (external repo + resources/)
├── .secret-seed            # Generated DB / S3 / Redis passwords
├── secrets.yaml            # ExternalSecrets: DB + S3 + Redis
├── vault/                  # Vault policy + k8s auth role + seed config
│   ├── policy.hcl
│   ├── k8s-auth-role.yaml
│   └── seed-mapping.conf
├── monitoring/             # PodMonitor + PrometheusRule
│   ├── pod-monitor.yaml
│   └── prometheus-rule.yaml
└── infra/                  # Cluster platform resources
    ├── gateway.yaml        #   → gateway-routes/ (on enable)
    ├── network-policy.yaml #   → resources/
    └── resource-quota.yaml #   → resources/
```

---

## `atlasctl seed`

Provisions PostgreSQL (database + user), MinIO (bucket + access keys), and writes credentials to Vault.

```bash
atlasctl seed aldoshkineg/seal
```

Reads `.secret-seed` and `vault/seed-mapping.conf`. Generated DB/S3/Redis credentials are automatically written to `secret/workloads/<group>/<app>/`.

### Options

| Flag        | Description                      |
| ----------- | -------------------------------- |
| `--dry-run` | Preview changes without applying |
| `--force`   | Skip validation checks           |

---

## `atlasctl enable`

Creates an ArgoCD Application CR in `gitops/workloads/<group>/<app>.yaml`, syncs manifests to `gitops/workloads/<group>/<app>/resources/`, copies `infra/gateway.yaml` to `gateway-routes/<app>.yaml`, and adds a TLS listener to the shared gateway.

```bash
# Preview
atlasctl enable aldoshkineg/seal --dry-run

# Enable + commit + push
atlasctl enable aldoshkineg/seal --sync --push
```

### Options

| Flag        | Description                             |
| ----------- | --------------------------------------- |
| `--dry-run` | Preview changes without applying        |
| `--sync`    | Commit changes to git                   |
| `--push`    | Push commits to remote (implies --sync) |
| `--force`   | Overwrite existing GitOps Application   |
| `-y`        | Skip confirmation prompt                |

---

## `atlasctl disable`

Removes gateway listener, ArgoCD Application CR from `gitops/workloads/`, gateway route file, and empty group directory.

```bash
# Preview
atlasctl disable aldoshkineg/seal --dry-run

# Disable
atlasctl disable aldoshkineg/seal -y

# Disable + commit + push
atlasctl disable aldoshkineg/seal -y --sync --push
```

### Options

| Flag        | Description                             |
| ----------- | --------------------------------------- |
| `--dry-run` | Preview changes without applying        |
| `--sync`    | Commit changes to git                   |
| `--push`    | Push commits to remote (implies --sync) |
| `-y`        | Skip confirmation prompt                |

---

## `atlasctl delete`

Deletes the `workloads/<group>/<app>/` directory. Refuses if the workload is still enabled.

```bash
atlasctl delete aldoshkineg/seal
atlasctl delete aldoshkineg/seal -y   # skip confirmation
```

---

## `atlasctl status`

Shows workload status — features, enabled state, gateway listener, ArgoCD sync status.

```bash
atlasctl status aldoshkineg/seal
atlasctl status aldoshkineg/seal --json
```

---

## `atlasctl list`

Lists all registered workloads with features and enabled status.

```bash
$ atlasctl list
Workloads:
  aldoshkineg/seal  [secrets gateway monitoring]
```

```bash
$ atlasctl list --json
[{"name":"aldoshkineg/seal","features":["secrets","gateway","monitoring"],"enabled":true,"gateway_listener":true}]
```

---

## Full Workflow

```bash
# 1. Scaffold
atlasctl new seal --group aldoshkineg \
  --repo https://github.com/aldoshkineg/atlas-idp.git \
  --repo-path charts/seal --helm

# 2. Customize (optional) — edit files, .secret-seed

# 3. Provision infrastructure
atlasctl seed aldoshkineg/seal

# 4. Promote to GitOps
atlasctl enable aldoshkineg/seal --dry-run
atlasctl enable aldoshkineg/seal --sync --push

# 5. Check status
atlasctl status aldoshkineg/seal

# 6. Disable
atlasctl disable aldoshkineg/seal --dry-run
atlasctl disable aldoshkineg/seal -y
atlasctl disable aldoshkineg/seal -y --sync --push
```

## Architecture (Go Rewrite)

```
tools/atlasctl/
├── main.go                 # Cobra root command
├── cmd/                    # Command implementations
│   ├── new.go
│   ├── seed.go
│   ├── enable.go
│   ├── disable.go
│   ├── delete.go
│   ├── status.go
│   └── list.go
├── pkg/                    # Shared packages
│   ├── template/           # Template rendering (templates/gold/)
│   ├── seed/               # DB/S3/Vault provisioning
│   ├── gitops/             # GitOps file management
│   ├── k8s/                # Kubernetes client wrapper
│   ├── vault/              # Vault API client
│   └── gateway/            # Gateway resource management
├── go.mod
├── Taskfile.yml          # build, test, vet, lint, cover, clean
└── README.md
```
