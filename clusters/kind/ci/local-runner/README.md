# GitHub Actions Runner (Self-Hosted)

Self-hosted GitHub Actions runner running in Docker. Automated via the GitHub CLI (`gh`).

## Prerequisites

- **GitHub CLI (`gh`)** installed and authenticated (`gh auth login`).
- Docker & Docker Compose.

## Quick Start

The setup is fully automated. The script will fetch a short-lived registration token via `gh`, resolve any existing container naming conflicts, and spin up the runner immediately.

```bash
make setup
# OR run the script directly:
./setup-runner.sh
