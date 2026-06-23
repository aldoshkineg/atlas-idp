# GHCR Registry Manager

A CLI tool to manage container images in the GitHub Container Registry for the `aldoshkineg` namespace.

## Prerequisites

- `GITHUB_TOKEN` in `.env` (at project root) with `read:packages` and `delete:packages` scopes
- `curl`, `python3`, `docker`

## Usage

```
./tools/ghcr/registry.sh list <package>
./tools/ghcr/registry.sh delete <package> <tag>
./tools/ghcr/registry.sh pull <package> <tag>
```

### Examples

```bash
# List all versions of seal-api
./tools/ghcr/registry.sh list seal-api

# Delete version tagged 0.2.0-alpha from seal-worker
./tools/ghcr/registry.sh delete seal-worker 0.2.0-alpha

# Pull seal-ui:0.2.0-alpha into local Docker
./tools/ghcr/registry.sh pull seal-ui 0.2.0-alpha
```
