# Velero — Cluster Backup & Restore

Velero backs up Kubernetes objects and persistent volumes to an in-cluster MinIO
(S3-compatible) bucket, using CSI snapshots on LINSTOR. Restore is not theoretical —
it is exercised by an automated e2e test.

## Components

| Component           | App manifest                                       | Chart / version                     | Namespace     | Wave |
| ------------------- | -------------------------------------------------- | ----------------------------------- | ------------- | ---- |
| MinIO               | `gitops/platform/storage/minio.yaml`               | `minio` 5.4.0                       | `minio`       | 5    |
| Velero              | `gitops/platform/storage/velero.yaml`              | `velero` 8.0.0 + AWS plugin v1.10.0 | `velero`      | 6    |
| snapshot-controller | `gitops/platform/storage/snapshot-controller.yaml` | external-snapshotter v8.6.0         | `kube-system` | 3    |
| snapshot CRDs       | `gitops/platform/base/snapshot-crds.yaml`          | external-snapshotter v8.6.0         | —             | —    |

## Our configuration

- **Backup target:** bucket `k8s-velero-backups` on MinIO
  (`http://minio.minio.svc.cluster.local:9000`, `s3ForcePathStyle: true`).
- **Credentials:** `existingSecret: velero-aws`, rendered by an `ExternalSecret` from
  Vault `secret/platform/minio` into an AWS-style `cloud` ini file — no keys in git.
- **CSI snapshots:** `EnableCSI` feature + `deployNodeAgent: true`; the default
  `VolumeSnapshotClass` is `linstor-csi-snapshot` (driver `linstor.csi.linbit.com`,
  pool `lvm-pool`), so PVC snapshots are taken at the DRBD/LVM-thin layer.
- **Schedule:** `weekly-pvc-backup` — every Sunday 02:00, TTL **336h (14 days)**,
  `defaultVolumesToFsBackup: true`.

MinIO itself: standalone, 1Gi PVC on `linstor-replicated`, auth via `minio-auth`
(Vault-backed), buckets provisioned by the chart: `k8s-velero-backups`, `cnpg-backups`,
`seal-outputs`. Exposed at `https://s3.atlas` (S3 API) and `https://console.s3.atlas`
(web console) through the platform gateway.

## Real usage

```bash
make test-velero       # full disaster-recovery drill
velero backup get      # list backups
velero backup create adhoc --include-namespaces <ns> --selector app=<name> --wait
velero restore create --from-backup <name> --wait
```

The e2e drill (`tests/velero/`, `tests/scripts/velero-test.sh`):

1. Creates a pod + 100Mi PVC (`linstor-replicated`) with ~10KB of data.
2. `velero backup create` scoped to the namespace/label; asserts `Completed`.
3. Verifies a `VolumeSnapshotContent` of class `linstor-csi-snapshot` exists.
4. Verifies backup objects landed in `k8s-velero-backups/backups/` (via `mc`).
5. **Deletes the pod and PVC** (simulated disaster).
6. `velero restore create`; waits for the pod, asserts the data is back.

A green `test-velero` therefore proves the entire chain:
CSI snapshot → S3 upload → object store → restore → data integrity.

## Known limitations

- MinIO is single-node inside the same cluster — this protects against namespace/PVC
  loss, not against loss of the whole cluster storage. Off-cluster replication of the
  MinIO bucket would close that gap.
- No backup of the `velero`/`minio` namespaces themselves (chicken-and-egg by design).

## See also

- [`cnpg.md`](cnpg.md) — database-level backups (Barman → same MinIO)
- [`linstor.md`](linstor.md) — the storage layer under the snapshots
