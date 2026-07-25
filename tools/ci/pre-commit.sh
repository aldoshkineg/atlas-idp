#!/usr/bin/env bash
set -euo pipefail

# Run pre-commit hooks across the whole repo.
exec pre-commit run --all-files
