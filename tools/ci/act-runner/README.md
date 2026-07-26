# Act Runner — Custom Docker Image for Local CI

Custom act runner image with preinstalled platform tools and persistent cache
mounts. Runs the same CI workflows locally (`.github/workflows/ci-*.yaml`) via
[nektos/act](https://github.com/nektos/act).

## Quick Start

```bash
# 1. Build the image (once, or after action.yml versions change)
make act-build

# 2. Run the CI workflow locally
make act-ci
```

If `make act-ci` fails with "image not found", run `make act-build` first.

## How It Works

- **`act-runner.sh build`** copies `install-tools.sh` from `tools/ci/`,
  parses tool versions from `.github/actions/tools/action.yml` via an explicit
  tool-to-variable map, generates install commands, builds `act-runner:latest`,
  then cleans up temp files from both `/tmp` and the build context.
- **`act-runner.sh ci`** validates required files, checks the image exists,
  creates cache directories, sources `.env`, and wraps `act` with the correct
  workflow, volume mounts, and selected secrets. Extra flags can be appended:
  `act-runner.sh ci --list`

All pinned versions live in `docs/requirements.md` (the `## Local CLI Tooling`
table) — a single source of truth shared by `install-tools.sh`, `preflight.sh`,
CI, and the act-runner image.
Installation logic comes from `tools/ci/install-tools.sh`.
No version duplication — the Dockerfile and `act-runner.sh` contain zero hardcoded
versions.

### .actrc

The project root `.actrc` provides default flags automatically read by `act`:

| Flag                                             | Purpose                                        |
| ------------------------------------------------ | ---------------------------------------------- |
| `-P self-hosted=act-runner:latest`               | Map `self-hosted` runner label to custom image |
| `--container-daemon-socket /var/run/docker.sock` | Docker-in-Docker for the CI runner             |
| `--pull=false`                                   | Use local image, never pull                    |

## Directory Layout

```
act-runner/
├── act-runner.sh       # Build & run script
├── Dockerfile          # Image definition
├── .dockerignore       # Build context exclusions
└── README.md
```

Temp build files (`install-tools.sh`) are written to the build context right before
`docker build`. The cleanup trap removes it from the build context on exit.

## Caching

Bind mounts at `/var/tmp/atlas/act_cache/` avoid redownloading on every run:

| Host path        | Container mount               | Contents                   |
| ---------------- | ----------------------------- | -------------------------- |
| `act_cache/tf`   | `/opt/terraform/plugin-cache` | Terraform provider plugins |
| `act_cache/home` | `/root/.cache`                | Trivy DB, pip cache, etc.  |

The Makefile's `TF_PLUGIN_CACHE_DIR` also points to `/var/tmp/atlas/act_cache/tf`,
so cache is shared between `make` and `act` runs.

## Requirements

- **act** v0.2+ (`go install github.com/nektos/act@latest` or `brew install act`)
- Docker
- CA certificates in `security/certs/ca.{crt,key}`
- `.env` file in project root with CI secret values
- `.secrets` file is not required; `act-runner.sh` passes secrets via `-s`

## Adding a New Tool

1. Add the pinned version to the `## Local CLI Tooling` table in `docs/requirements.md`
2. Add an install case to `tools/ci/install-tools.sh`
3. Rebuild: `make act-build`
