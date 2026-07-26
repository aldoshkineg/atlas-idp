# Tests

Resources and runners for platform verification.

## Directory convention

- `tests/` (this directory) — **platform-level e2e** suites. Each `tests/<suite>/`
  holds the deploy manifests; the matching `tests/scripts/<suite>-test.sh` deploys
  and verifies them.
- `apps/<app>/tests/` — **per-application** tests (unit, integration, load), e.g.
  `apps/seal/tests/integration` and `apps/seal/tests/load` (k6). These are owned by
  each project, not by the platform test harness.

## Run All Tests

```bash
make test
```

Each target deploys and verifies itself.

## Individual Targets

| Command                    | What it does                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------- |
| `make test-ca-gateway`     | Deploy CA TLS test app and verify endpoint                                             |
| `make test-vault`          | Seed Vault, deploy injection pod, verify secrets                                       |
| `make test-velero`         | Backup pod with PVC to MinIO, disaster, restore                                        |
| `make test-network-policy` | Test NetworkPolicy isolation between 3 pods                                            |
| `make test-keda`           | Test KEDA autoscaling via ConfigMap trigger                                            |
| `make test-db-backup`      | Test CNPG backup/restore to MinIO                                                      |
| `make test-seal`           | Test Seal deployment (pods, API, document CRUD, worker metrics, MinIO bucket, gateway) |
| `make test-argocd-rollout` | Test Argo Rollouts canary (controller, CRD, weight steps, promotion, scale-down)       |
| `make test-undeploy`       | Remove all test resources                                                              |
