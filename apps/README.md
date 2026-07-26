# Applications (`apps/`)

Source projects owned by the platform team, distinct from tenant workloads. Seal is a demonstration workload: it lives in-repo to exercise the full platform pipeline (atlasctl → GitOps → Vault → Gateway) and the image build/sign flow (GHCR + cosign).

## What lives here

- **Application source** — code, Helm charts, and per-app tests for projects the
  platform ships, e.g. `apps/seal/` (API, worker, UI, charts, `tests/`).
- **Per-app tests** — `apps/<app>/tests/` holds unit / integration / load suites
  (e.g. `apps/seal/tests/integration`, `apps/seal/tests/load` with k6). These are
  run by each project's own CI, not by the platform `tests/` harness.

## How it differs from other directories

| Directory           | Role                                                               |
| ------------------- | ------------------------------------------------------------------ |
| `apps/`             | Source projects (code, charts, per-app tests)                      |
| `workloads/`        | Tenant applications managed by `atlasctl` (single source of truth) |
| `gitops/workloads/` | Generated Argo CD Applications produced by `atlasctl enable`       |

`apps/` is for things the platform builds and publishes; `workloads/` is for
tenants onboarded through the golden-path pipeline.
