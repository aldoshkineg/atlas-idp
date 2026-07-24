# Security Certificates

Self-signed `ca.crt` / `ca.key` live here. The same root is loaded into the
`cert-manager` ClusterIssuer `atlas-ca-issuer` (secret `cert-manager/atlas-ca-secret`)
and used to issue in-cluster TLS certificates (gateway routes, webhooks, etc.).

> **CI note:** these files are no longer uploaded to GitHub as separate secrets.
> `make gh-seed` embeds them as base64 (`ATLAS_CA_CRT_B64` / `ATLAS_CA_KEY_B64`)
> into `.env`, which is shipped to CI as the single `ENV_FILE` secret. The `ci-base`
> "Load ENV_FILE" step re-materialises `security/certs/ca.{crt,key}` before Terraform
> runs, so the on-disk files are optional for CI/act once `.env` carries the base64.

> Note: this CA is **not** trusted by the system by default. Clients (browser,
> `curl`, `kubectl`, other pods) will reject the issued certificates until the
> root is added to their trust store. The steps below trust it on the **local host only**.

## Trust the root CA on the local host

The CA must be copied into the OS trust store. The path/tool depends on the distro.

### Arch Linux (update-ca-trust)

```bash
sudo cp security/certs/ca.crt /etc/ca-certificates/trust-source/anchors/atlas.crt
sudo chmod 644 /etc/ca-certificates/trust-source/anchors/atlas.crt
sudo update-ca-trust
```

Verify:

```bash
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt security/certs/ca.crt
# expected: security/certs/ca.crt: OK
```

### Debian / Ubuntu (update-ca-certificates)

```bash
sudo cp security/certs/ca.crt /usr/local/share/ca-certificates/atlas.crt
sudo chmod 644 /usr/local/share/ca-certificates/atlas.crt
sudo update-ca-certificates
```

### For workloads / nodes

- **Talos nodes**: add the CA to the machine config `trust` section (via the
  `talos-config` module) so node-level clients trust it.
- **Kubernetes pods**: deploy cert-manager Trust Manager and inject the CA into
  pod trust bundles for service-to-service TLS.
