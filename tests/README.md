# Test Resources

Test manifests for platform service verification.

## Test TLS

Requires `/etc/hosts` entry: `127.0.0.1 test-ca.atlas`

```bash
curl --cacert clusters/kind/certs/ca.crt https://test-ca.atlas/
```

## Test Vault Injection

```bash
kubectl apply -f tests/vault/
kubectl logs -n testing vault-inject-test
```