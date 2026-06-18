# Act Runner — Custom Docker Image for Local CI

Custom act runner image with preinstalled platform tools and persistent cache
mounts. Runs the same CI workflow (`.github/workflows/ci.yaml`) locally via
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

- **`act-runner.sh build`** copies `install-tools.sh` from `.github/scripts/`,
  parses tool versions from `.github/actions/tools/action.yml` via an explicit
  tool-to-variable map, generates install commands, builds `act-runner:latest`,
  then cleans up temp files from both `/tmp` and the build context.
- **`act-runner.sh ci`** validates required files, checks the image exists,
  creates cache directories, sources `.env`, and wraps `act` with the correct
  workflow, volume mounts, and selected secrets. Extra flags can be appended:
  `act-runner.sh ci --list`

All version numbers come from `.github/actions/tools/action.yml` at build time.
Installation logic comes from `.github/scripts/install-tools.sh`.
No version duplication — the Dockerfile itself contains zero hardcoded versions.

### .actrc

The project root `.actrc` provides default flags automatically read by `act`:

| Flag                                             | Purpose                                        |
| ------------------------------------------------ | ---------------------------------------------- |
| `-P self-hosted=act-runner:latest`               | Map `self-hosted` runner label to custom image |
| `--container-daemon-socket /var/run/docker.sock` | Docker-in-Docker for KinD                      |
| `--pull=false`                                   | Use local image, never pull                    |

## Directory Layout

```
act-runner/
├── act-runner.sh       # Build & run script
├── Dockerfile          # Image definition
├── .dockerignore       # Build context exclusions
└── README.md
```

Temp build files (`install-tools.sh`, `install-cmds.sh`) are written to `/tmp`
and copied into the build context right before `docker build`. The cleanup trap
removes them from both locations on exit.

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

1. Add version variable to `.github/actions/tools/action.yml` (e.g. `NEWTOOL_VERSION: "x.y.z"`)
2. Add install case to `.github/scripts/install-tools.sh`
3. Add tool-to-variable mapping to the `TOOL_VARS` associative array in `act-runner.sh`
4. Rebuild: `make act-build`
