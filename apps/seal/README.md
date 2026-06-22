# Seal — PDF Signing & Generation Platform

A production-grade PDF signing and document generation platform with REST API, async worker, and web UI.

## Architecture

- **seal-api** — REST API (Go, chi, pgx, Redis)
- **seal-worker** — PDF factory: reads jobs from Redis, generates PDFs, signs with CMS/PAdES, uploads to MinIO
- **seal-ui** — Web frontend (Go + HTMX)

## Quick Start

```bash
go-task dc-up        # Start all services via Docker Compose
go-task gen-certs    # Generate dev TLS certs (first time only)
```

## Development

See `ARCHITECTURE.md` for detailed architecture and `Taskfile.yml` for available commands.
