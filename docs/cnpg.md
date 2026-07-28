# CloudNativePG — PostgreSQL Operator

CloudNativePG (CNPG) runs the platform PostgreSQL (`production-db`) with WAL archiving
and scheduled backups to MinIO via the Barman Cloud plugin. Backup **and restore** are
verified by an automated test.

## Components

| Component        | App manifest                                      | Chart / version                              | Namespace     | Wave |
| ---------------- | ------------------------------------------------- | -------------------------------------------- | ------------- | ---- |
| CNPG operator    | `gitops/platform/storage/cnpg-operator.yaml`      | `cloudnative-pg` 0.28.3                      | `cnpg-system` | 1    |
| Barman plugin    | `gitops/platform/storage/cnpg-barman-plugin.yaml` | `plugin-barman-cloud` 0.7.0                  | `cnpg-system` | 2    |
| postgres-cluster | `gitops/platform/storage/postgres-cluster.yaml`   | raw manifests (`resources/postgres-cluster`) | `database`    | 9    |

## Our configuration

`Cluster production-db` (`gitops/platform/storage/resources/postgres-cluster/cluster.yaml`):

- PostgreSQL **17.6**, `instances: 1`, 1Gi storage on **`linstor-replicated`** (HA comes
  from DRBD block replication, not from Postgres streaming replicas).
- `primaryUpdateStrategy: unsupervised`; `max_connections: 100`, `shared_buffers: 64MB`.
- Barman Cloud plugin enabled as WAL archiver → `ObjectStore production-db-backup`.

Backup pipeline (`objectstore.yaml`, `scheduled-backup.yaml`):

- Destination `s3://cnpg-backups/` on MinIO (`http://minio.minio.svc.cluster.local:9000`).
- WAL compression `gzip`, `maxParallel: 2`, **retention 7d**.
- `ScheduledBackup production-db-weekly` — every Sunday 03:00.
- S3 credentials come from the `production-db-backup` Secret, produced by an
  `ExternalSecret` from Vault `secret/platform/minio` — nothing in git.

Consumers: the `seal` reference workload connects to
`production-db-rw.database.svc.cluster.local:5432`; per-workload databases/users are
provisioned by `atlasctl seed` (see [`workloads.md`](workloads.md)). Metrics are scraped
by a `PodMonitor` (`gitops/platform/observability/resources/monitor/postgres-pod-monitor.yaml`).

## Real usage

```bash
make test-db-backup                 # e2e backup + recovery drill
kubectl get cluster -n database     # cluster status (primary, ready instances)
kubectl get backup -n database      # backup objects and phases
```

The e2e drill (`tests/db-backup/`, `tests/scripts/db-backup-test.sh`):

1. Creates a source `Cluster` with Barman archiving to `cnpg-backups`.
2. Inserts 100 rows via `psql`.
3. Takes a `Backup` (`method: plugin`); waits for `completed`.
4. Bootstraps a **recovery cluster** from that backup (`bootstrap.recovery` +
   `externalClusters`).
5. Asserts all 100 rows are present in the recovered database.

Note the zero-trust interplay: the test temporarily applies an extra
CiliumNetworkPolicy (`tests/db-backup/minio-access.yaml`) so its namespace can reach
MinIO `:9000`, and removes it in cleanup — production `platform-ingress` policies are
never widened (see [`security.md`](security.md)).

`recipes/cnpg-backup/` contains the same backup stack as a standalone `kubectl apply -k`
snippet for ad-hoc use — it is deliberately **not** referenced by Argo CD
(see `recipes/README.md`).

## Known limitations

- `instances: 1` — pod-level HA is delegated to DRBD-replicated storage; scaling to 2–3
  instances is a values change, at the cost of RAM on the lab hosts.
- PITR is possible (WAL archive is continuous) but only full-backup recovery is
  currently exercised by tests.

## See also

- [`velero.md`](velero.md) — cluster-level backups to the same MinIO
- [`vault.md`](vault.md) — where the S3 credentials come from
