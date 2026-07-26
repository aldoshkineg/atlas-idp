# Atlas IDP CI Process

Description of how continuous integration is organized in this repository: which
workflows exist, how they are triggered, what they consist of, and how to run
them locally / via a self-hosted runner.

## Component Overview

| File                                        | Purpose                                                                               |
| ------------------------------------------- | ------------------------------------------------------------------------------------- |
| `.github/workflows/ci-all.yaml`             | Orchestrator. Chains phases into one pipeline.                                        |
| `.github/workflows/ci-base.yaml`            | **base** phase: `terraform apply` (Incus/Talos) + seed Vault.                         |
| `.github/workflows/ci-middleware.yaml`      | **middleware** phase: sync platform layers (storage/security/delivery/observability). |
| `.github/workflows/ci-workload.yaml`        | **workload** phase: seed + sync workload layer (seal).                                |
| `.github/workflows/ci-destroy.yaml`         | Destroy infrastructure (requires `confirm: "destroy"`).                               |
| `.github/workflows/ci-destroy-force.yaml`   | Full teardown (Incus/Talos + TF state).                                               |
| `.github/workflows/security.yaml`           | Trivy scan of the whole repo (IaC/CVE/secrets).                                       |
| `.github/workflows/seal-docker-publish.yml` | Build/push/sign seal images (on tag `v*`).                                            |
| `.github/workflows/atlasctl-release.yml`    | Release `atlasctl` (on tag `v*`).                                                     |

### Composite Actions (reusable steps)

| Action                        | What it does                                                                                                                                                                 |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/actions/load-env`    | Replays the `ENV_FILE` secret into `.env` + exports to `$GITHUB_ENV` (with masking). Optionally materialises CA (`materialise_ca`) and derives cosign key (`derive_cosign`). |
| `.github/actions/cluster-env` | Sets `KUBECONFIG` and `TF_PLUGIN_CACHE_DIR` in `$GITHUB_ENV`.                                                                                                                |
| `.github/actions/tools`       | Installs selected CLIs via `tools/ci/install-tools.sh` (`VERSION_MAP`).                                                                                                      |
| `.github/actions/terraform`   | `init` → `plan` → `apply` + node check + CA secret for cert-manager.                                                                                                         |
| `.github/actions/lint`        | `terraform fmt -check`, `terraform validate`, `yamllint`.                                                                                                                    |
| `.github/actions/scan`        | `trivy fs` (vuln/secret/misconfig).                                                                                                                                          |
| `.github/actions/seed-vault`  | Port-forward Vault + `seed-vault.sh`.                                                                                                                                        |

### Scripts (`tools/ci/`)

- `install-tools.sh` — single source of truth for toolchain versions (`VERSION_MAP`), including `jq`.
- `terraform-init.sh` — `terraform init` with retry.
- `sync-layers.sh` — sync ArgoCD layers; parses `argocd app get -o json | jq`; includes a **health-gate** (fails if layer is not `Synced/Healthy`).
- `seed-gh.sh` — uploads `.env` into the `ENV_FILE` secret.
- `stage-terraform-destroy.sh` — force-teardown.

## Triggers

| Event                            | What gets triggered                                                                                                                                       |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `push` to `main`                 | `ci-all` → full pipeline (lint → base → middleware → workload). If the commit contains `[base]` / `[middleware]` / `[workloads]` — **only** those phases. |
| `pull_request` to `main`         | `ci-all` → **lint only** (no cluster mutation).                                                                                                           |
| `workflow_dispatch`              | `ci-all` → phases controlled by `run_base` / `run_middleware` / `run_workloads` toggles (all `true` by default).                                          |
| tag `v*`                         | `seal-docker-publish` + `atlasctl-release` (build/publish/sign).                                                                                          |
| `push`/`PR` to `main` (security) | `security` — Trivy scan.                                                                                                                                  |

Destroy workflows (`ci-destroy`, `ci-destroy-force`) are **not** triggered automatically — manual only (`workflow_dispatch`), and `ci-destroy` requires `confirm: "destroy"`.

## Orchestrator `ci-all`

```
gate ──▶ lint ──▶ base ──▶ middleware ──▶ workloads
```

- **`gate`** (ubuntu-latest) — cheap step. Parses the commit message and
  sets `sel_base` / `sel_middleware` / `sel_workloads`:
  - no `[base]`/`[middleware]`/`[workloads]` tokens → all `true` (full pipeline);
  - token(s) present → `true` only for matching phases.
- **`lint`** runs on a self-hosted runner (reuses toolchain cache) and
  acts as a gate: if fmt/validate/yamllint fail, apply does not proceed.
- **Phases** — calls to reusable workflows (`uses:`). Each inherits
  `concurrency: atlas-stage`, so two mutating phases never run
  simultaneously (destroy does not overlap with apply).
- **`workflow_dispatch`** for phases ignores the commit selector and uses
  `run_*` toggles instead.

> ⚠️ The selector triggers on **any** occurrence of a token in the commit text. If a
> message incidentally contains `[base]` (e.g., "refactor [base] module"), only the
> base phase will run.

### Why `pull_request` is lint-only

Applying `terraform apply` on the shared stage cluster from a PR is dangerous and
pointless. PRs serve to validate (fmt/validate/yamllint) before merge, without
mutating infrastructure.

## Secrets

The only repo secret needed by mutating workflows is **`ENV_FILE`**. It contains
the entire local `.env` (Vault seeds, CA cert/key, cosign key, tokens). It is
uploaded with one command and replayed inside the runner:

```bash
make seed-gh   # -> ./tools/vault/seed-gh.sh (reads .env, uploads to ENV_FILE)
```

Inside CI, `load-env` writes `.env`, exports each variable to `$GITHUB_ENV` with
`::add-mask::` (log masking), and optionally materialises the CA. After `ci-base`,
the working copy is cleaned up (`rm -f .env security/certs/*`) at
`if: always()`, so secrets do not persist on the persistent self-hosted runner.

> The cosign key in `ENV_FILE` has an empty password (`COSIGN_PASSWORD: ""` in
> `seal-docker-publish.yml`) — signing is effectively unprotected. Plan: migrate to
> keyless (Fulcio/OIDC) or set a real password.

## Local Run vs Cloud Self-Hosted Runner

GitHub workflows use **reusable calls** (`uses:`), which `act`
(the local emulator) cannot execute. Therefore, phases are run locally
directly via `tools/ci/act-runner/act-runner.sh`, not through `ci-all`:

```bash
make act-ci            # base -> middleware -> workload (sequentially, via act)
make act-stage-base    # base only
make act-destroy       # ci-destroy via act
```

For actual runs in GitHub, a **self-hosted runner**
(`myoung34/github-runner`, label `self-hosted`) is used, brought up via
`tools/ci/local-runner`:

```bash
make ci-runner-up      # bring up runner (Docker + Incus + /var/tmp/atlas)
make ci-runner-ci      # dispatch ci-all in GitHub (via runner)
make ci-runner-down    # stop
```

The runner must have access to the Docker socket, Incus socket, and `/var/tmp/atlas`
(where kubeconfig/talos artifacts and cache reside).

## Useful Make Targets

| Target                                                        | Action                                          |
| ------------------------------------------------------------- | ----------------------------------------------- |
| `make act-ci`                                                 | Full pipeline locally (act).                    |
| `make ci-runner-ci`                                           | Full pipeline in GitHub via self-hosted runner. |
| `make seed-gh`                                                | Upload `.env` to `ENV_FILE` secret.             |
| `make validate`                                               | terraform fmt/validate + yamllint + trivy.      |
| `make pre-commit`                                             | Pre-commit hooks.                               |
| `make ci-runner-{base,middle,workload,destroy,destroy-force}` | Individual phases via runner.                   |

## Security Notes / Best Practices

- Least-privilege `permissions` (mutating workflows use `{}` + per-job `contents: read`).
- `security` has its own `concurrency` (`security-<ref>`) and does not block infra runs.
- `actions/checkout` everywhere uses `persist-credentials: false`; all steps use `set -euo pipefail`.
- All third-party actions are pinned by tag (`@v4`, `@v3` …) — candidates for SHA-pinning + Dependabot.
- `sync-layers.sh` has a health-gate: green CI now means layers are actually `Synced/Healthy`.
