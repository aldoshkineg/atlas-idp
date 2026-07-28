# CA & TLS Certificate Issuance

This document describes how TLS certificates are issued for the project's local
domain (`.atlas`) using a private root CA and cert-manager.

## Overview

Atlas IDP runs a private Public Key Infrastructure rooted at a self-signed
**root CA**. cert-manager uses that CA to issue per-service TLS certificates for
the project domain `*.atlas` (e.g. `argocd.atlas`, `seal.atlas`, `vault.atlas`).
The Gateway (Gateway API) routes terminate TLS with these certificates and
service-to-service traffic trusts them once the root CA is in the trust store.

```
security/certs/ca.{crt,key}          (local, git-ignored)
        │  base64 → .env (ATLAS_CA_CRT_B64 / ATLAS_CA_KEY_B64)
        │  make seed-gh → GitHub secret ENV_FILE
        ▼
CI ci-base "Load ENV_FILE"  →  re-materialises security/certs/ca.{crt,key}
        │
        ▼
terraform-incus action: kubectl create secret tls atlas-ca-secret -n cert-manager
        │
        ▼
cert-manager ClusterIssuer atlas-ca-issuer   (ca: secretName: atlas-ca-secret)
        │
        ▼
Certificate resources (seal-cert, argocd-cert, …) → <service>.atlas certs
        │
        ▼
Gateway API routes (TLS) + in-cluster trust
```

## CA key material (the files)

The root CA consists of two files under `security/certs/`:

| File     | Purpose                      | Committed?       |
| -------- | ---------------------------- | ---------------- |
| `ca.crt` | Root CA certificate (public) | No (git-ignored) |
| `ca.key` | Root CA private key          | No (git-ignored) |

Both are matched by `security/certs/ca*` in `.gitignore` and must **never** be
committed — they are generated once on the operator's machine and kept locally.
The keys live in these files; for CI they are additionally base64-encoded into
`.env` (see below).

To (re)generate the root CA (example with `openssl`):

```bash
openssl genrsa -out security/certs/ca.key 2048
openssl req -x509 -new -nodes -key security/certs/ca.key \
  -subj "/CN=atlas-root-ca" -days 3650 -out security/certs/ca.crt
```

> Keep `ca.key` secret. Anyone holding it can issue trusted certificates for the
> domain.

## Distributing the CA to CI

The CA files are not uploaded as separate GitHub secrets. They are base64-
embedded into `.env` and shipped as the single `ENV_FILE` secret:

1. Embed the CA into `.env` (manual, one time — see `.env.example`):
   ```bash
   ATLAS_CA_CRT_B64=$(base64 -w0 < security/certs/ca.crt)
   ATLAS_CA_KEY_B64=$(base64 -w0 < security/certs/ca.key)
   ```
2. Upload: `make seed-gh` → `gh secret set ENV_FILE < .env`.
3. In CI, the `ci-base` "Load ENV_FILE" step writes `.env` and re-materialises
   `security/certs/ca.{crt,key}` from base64 before Terraform runs.

## cert-manager wiring

- **ClusterIssuer `atlas-ca-issuer`**
  (`gitops/platform/base/resources/cert-manager/issuers.yaml`) references the CA
  via a `ca` issuer backed by the `atlas-ca-secret` TLS secret.
- **`atlas-ca-secret`** (namespace `cert-manager`) is a `tls` secret holding the
  CA cert+key. It is **not** GitOps-managed — it is created by the
  `terraform-incus` composite action during `ci-base` from the reconstructed
  `security/certs/ca.{crt,key}`. If this secret is missing, the issuer cannot
  sign.
- **Per-service `Certificate`** resources under
  `gitops/platform/base/resources/gateway-routes/*.yaml` request certs from
  `atlas-ca-issuer` for their `<service>.atlas` DNS name and are consumed by the
  matching Gateway API `HTTPRoute`.

### Services on the `.atlas` domain

| DNS name           | Certificate resource |
| ------------------ | -------------------- |
| `argocd.atlas`     | `argocd-cert`        |
| `argocd-cli.atlas` | `argocd-cli-cert`    |
| `seal.atlas`       | `seal-cert`          |
| `grafana.atlas`    | `grafana-cert`       |
| `vault.atlas`      | `vault-cert`         |
| `s3.atlas`         | `minio-cert`         |
| `console.s3.atlas` | `minio-cert`         |

## Trusting the root CA

The root CA is **not** trusted by the system by default. Clients (browser,
`curl`, `kubectl`, pods) reject issued certificates until the root is added to
their trust store.

### Local host

**Arch Linux**

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

**Debian / Ubuntu**

```bash
sudo cp security/certs/ca.crt /usr/local/share/ca-certificates/atlas.crt
sudo chmod 644 /usr/local/share/ca-certificates/atlas.crt
sudo update-ca-certificates
```

### Talos nodes

Add the CA to the machine config `trust` section (via the `talos-config` module)
so node-level clients trust it.

### Kubernetes pods

Deploy cert-manager Trust Manager and inject the CA into pod trust bundles for
service-to-service TLS.

## Verification

See [`runbooks/cert-verification.md`](runbooks/cert-verification.md) for a full
verification checklist (CA fingerprint, SAN/validity, trust-store checks).

Quick checks:

```bash
# CA fingerprint
openssl x509 -in security/certs/ca.crt -fingerprint -sha256 -noout

# Issued certificate details (SAN, issuer)
openssl x509 -in <cert>.crt -subject -issuer -noout
```
