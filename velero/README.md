# Velero (Backup / DR)

Disaster-recovery configuration for the platform.

- **Backup configuration**: `gitops/platform/storage/velero.yaml` — Velero install plus
  `BackupStorageLocation` / `VolumeSnapshotLocation` backed by MinIO.
- **Restore drills / procedures**: `docs/runbooks/` (cluster recovery from Velero).
- **Test**: `make test-velero` (see `tests/README.md`).

This directory is intentionally light: the live configuration is GitOps-managed under
`gitops/platform/storage/`, not hand-edited here.
