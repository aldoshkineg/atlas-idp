# GitHub Actions Runner (Self-Hosted)

Self-hosted GitHub Actions runner running in Docker, executing the repo's real
CI workflows (`ci-base`, `ci-middleware`, `ci-workload`, `ci-all`) on `push`/
`pull_request`/`workflow_dispatch`. Automated via the GitHub CLI (`gh`).

> For isolated, GitHub-free local CI, prefer `make act-ci` (see
> `tools/ci/act-runner`). This runner connects to GitHub and runs the actual
> workflows on your machine when they are triggered in the repo.

## Prerequisites

- **GitHub CLI (`gh`)** installed and authenticated (`gh auth login`).
- **Docker & Docker Compose** (daemon reachable via `/var/run/docker.sock`).
- **Incus** running on the host — the `terraform-incus` action drives the Talos
  cluster through `/var/lib/incus/unix.socket`.
- **`/var/tmp/atlas`** present on the host (holds the generated Talos
  kubeconfig / talosconfig and caches consumed by the jobs).
- **Repository secrets** configured in GitHub
  (`Settings → Secrets → Actions`): `ATLAS_CA_CRT`, `ATLAS_CA_KEY`,
  `VL_MINIO_ROOT_USER`, `VL_MINIO_ROOT_PASSWORD`, `VL_REDIS_PASSWORD`,
  `VL_GRAFANA_PASSWORD`. These are passed to `ci-base` and consumed by the
  vault-seeds step.

The runner job itself has no `container:`, so it executes directly inside the
runner container. The `Install Tools` action downloads the required CLIs
(vault, terraform, kubectl, kind, trivy, yamllint, incus, argocd, atlasctl)
on each run, so no pre-installed toolchain is required in the image.

## Quick Start

```bash
make ci-runner-up        # fetch token via gh, start the runner container
make ci-runner-status    # docker compose ps
make ci-runner-logs      # docker compose logs -f
make ci-runner-down      # docker compose down
```

Or operate from this directory directly:

```bash
make setup      # ./setup-runner.sh
make status
make logs
make remove     # docker compose down -v (wipes local runner state)
```

Runner state lives in Docker named volumes. Use `make remove` / `docker compose down -v`
to reset it.

## Important notes

- **Base image is `ubuntu-noble` (24.04, glibc 2.39)**, not the `latest` tag
  (20.04, glibc 2.31). `atlasctl` requires glibc >= 2.34 and Ubuntu 24.04's pip
  needs `PIP_BREAK_SYSTEM_PACKAGES=1` (both already set in the compose).
- **The runner workdir is `RUNNER_WORKDIR=/var/tmp/atlas/gh-work`** — i.e. under
  the host-visible `/var/tmp/atlas` bind mount. Terraform's incus disk devices
  use absolute source paths (e.g. `abspath(path.module)/zot-config.json`) that
  incus evaluates on the **host**. Keeping the checkout under `/var/tmp/atlas`
  makes those paths resolve on the host; a container-local workdir (the default
  `/_work`) makes incus fail with `Missing source path`.
- The `actions/tools` step downloads the toolchain on the first job of a fresh
  container and reuses it for later jobs via a `command -v` guard. On container
  recreation the tools are re-downloaded once.

Once up, trigger a run from the repo (`Actions → CI All → Run workflow`) or push
to `main`; the job is picked up by this runner and runs on your machine.
