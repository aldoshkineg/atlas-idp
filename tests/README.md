# Test Resources

Test manifests for platform service verification.

## Run All Tests

```bash
make test
```

This runs: gateway TLS → Vault seed → Velero backup/restore → final checks.

## Individual Targets

| Command | What it does |
|---------|-------------|
| `make test-gateway` | Deploy TLS test app + certificate |
| `make test-vault` | Deploy Vault injection test pod |
| `make test-seed` | Create Vault K8s auth role + test secret |
| `make test-velero` | Backup pod with PVC to MinIO, disaster, restore |
| `make test-check` | Verify TLS endpoint + Vault injection |
| `make test-undeploy` | Remove all test resources |