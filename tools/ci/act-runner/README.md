# Act Runner — Custom Docker Image for Local CI

Custom act runner image with preinstalled tools and persistent bind mount cache.

## Included Tools

| Tool      | Version |
| --------- | ------- |
| terraform | 1.15.3  |
| kubectl   | 1.34.0  |
| kind      | 0.29.0  |
| trivy     | 0.70.0  |
| yamllint  | 1.35.1  |

Versions are synced with `.github/actions/tools/action.yml`.

## Quick Start

```bash
# 1. Build the image (once, or after Dockerfile changes)
make act-build

# 2. Run the CI workflow via act
make act-ci
```

## How It Works

- **`make act-build`** builds `act-runner:latest` from `tools/ci/act-runner/Dockerfile`
- **`make act-ci`** runs `act` with flags from `.actrc`:
  - `-P self-hosted=act-runner:latest` / `-P ubuntu-latest=act-runner:latest` — map runners to custom image
  - `--container-daemon-socket /var/run/docker.sock` — Docker-in-Docker support
  - `--env-file .env` / `--secret-file .secrets` — env vars and secrets
  - `--pull=false` — skip pulling the image on each run
  - Additional mounts for terraform plugin cache and home cache
  - `DEV_CA_CRT` and `DEV_CA_KEY` injected from `security/certs/`

## Directory Layout

```
act-runner/
├── Dockerfile        # Image definition
├── .dockerignore
├── README.md
└── cache/
    ├── tf/           → mounted to /opt/terraform/plugin-cache
    └── home/         → mounted to /root/.cache
```

## Caching

Bind mounts in `cache/` avoid redownloading on every run:

- **Terraform providers** → `cache/tf/` (`TF_PLUGIN_CACHE_DIR`)
- **Trivy DB**, pip cache, etc. → `cache/home/` (`~/.cache`)

To purge all cache:

```bash
rm -rf tools/ci/act-runner/cache/tf/* tools/ci/act-runner/cache/home/*
```

## Manual Run

```bash
act -W .github/workflows/ci.yaml \
  -s DEV_CA_CRT="$(cat security/certs/ca.crt)" \
  -s DEV_CA_KEY="$(cat security/certs/ca.key)"
```

Or via make:

```bash
make act-ci
```

## Requirements

- **act** v0.2+ (`go install github.com/nektos/act@latest` or `brew install act`)
- Docker
- CA certificates in `security/certs/ca.{crt,key}`
- `.secrets` file in project root (created via `make github-secrets-ca` or manually)
- `.env` file in project root (optional, for env vars like `AWS_REGION`)
