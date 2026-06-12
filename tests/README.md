# Test Resources

Test manifests for platform service verification.

## Run All Tests

```bash
make test
```

Each target deploys and verifies itself.

## Individual Targets

| Command | What it does |
|---------|-------------|
| `make test-ca-gateway` | Deploy CA TLS test app and verify endpoint |
| `make test-vault` | Seed Vault, deploy injection pod, verify secrets |
| `make test-velero` | Backup pod with PVC to MinIO, disaster, restore |
| `make test-network-policy` | Test NetworkPolicy isolation between 3 pods |
| `make test-keda` | Test KEDA autoscaling via ConfigMap trigger |
| `make test-undeploy` | Remove all test resources |