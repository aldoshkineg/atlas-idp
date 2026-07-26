# Setup — Getting Started

This guide takes a fresh clone from zero to a host that is ready to bootstrap
the Atlas IDP cluster with `act` (or the self-hosted runner). It covers the
three things you must do before any pipeline runs:

1. Create `.env` (and `.secrets`).
2. Prepare the startup images in Incus.
3. Pass `make preflight`.

All repository secrets are **git-ignored** — generate them locally and never
commit them.

---

## 1. Prerequisites

- A Linux host with **Incus** installed and its daemon running
  (`/var/lib/incus/unix.socket` must exist). The cluster runs as Incus VMs.
- **Docker** (with the `compose` and `buildx` plugins) — `act` executes the
  CI workflows inside a local `act-runner` container that mounts the Incus
  socket.
- The CLI toolchain pinned in `REQUIREMENTS.md` (pre-commit, terraform,
  kubectl, helm, argocd, age, yq, trivy, docker, docker compose, docker
  buildx, go-task, gh, act, jq, velero, mc, yamllint, shellcheck, gitleaks,
  golangci-lint).
- **Memory**:
  - **Minimum 8 GB RAM** to run the project at all (hard floor enforced by
    `make preflight`).
  - **12 GB RAM** recommended to run the **base layer**: 3 Talos nodes hosting
    Argo CD, Linstor, Vault, Gateway API and External Secrets Operator (ESO).
  - **~32 GB RAM** — for a **full** run of all platform layers (monitoring
    stack, MinIO, CloudNativePG/Postgres, Redis, KEDA, Seal workloads, …).

`make preflight` (section 5) verifies all of the above.

---

## 2. Configure secrets (`.env`)

Copy the template and fill it in:

```bash
cp .env.example .env
```

### Vault platform seeds

Set the following to the values you want seeded into the in-cluster Vault by
the `ci-base` → `seed-vault` step:

- `VAULT_TOKEN`
- `VL_MINIO_ROOT_USER` / `VL_MINIO_ROOT_PASSWORD`
- `VL_REDIS_PASSWORD`
- `VL_GRAFANA_PASSWORD`

> These are consumed by `tools/vault/seed-vault.sh` via the `VL_*` vars and
> written to Vault; the cluster services read them back through External
> Secrets.

### Root CA (required — this is the "drop certificates" step)

The pipeline materialises a root CA from `.env` into
`security/certs/ca.{crt,key}` and creates the `atlas-ca-secret` TLS secret in
`cert-manager`. Generate the CA once (see `docs/CA.md` for the full PKI
flow):

```bash
openssl genrsa -out security/certs/ca.key 2048
openssl req -x509 -new -nodes -key security/certs/ca.key \
  -subj "/CN=atlas-root-ca" -days 3650 -out security/certs/ca.crt
```

Then base64-embed the cert **and** key into `.env`:

```bash
ATLAS_CA_CRT_B64=$(base64 -w0 < security/certs/ca.crt)
ATLAS_CA_KEY_B64=$(base64 -w0 < security/certs/ca.key)
```

### Cosign signing key

The Seal images are verified with cosign in-cluster (Kyverno). Generate the
keypair (see `docs/cosign.md`); the public key `security/cosign/cosign.pub` is
already committed, the private key stays local:

```bash
cosign generate-key-pair --output-key-prefix security/cosign/cosign
# leave the passphrase empty (press Enter twice)
```

Base64-embed the private key into `.env`:

```bash
COSIGN_PRIVATE_KEY_B64=$(base64 -w0 < security/cosign/cosign.key)
```

### Optional: upload to GitHub for the self-hosted runner

If you drive the pipeline via the self-hosted runner (`ci-runner-*`) instead of
local `act`, publish the whole `.env` as the single `ENV_FILE` secret:

```bash
make seed-gh   # gh secret set ENV_FILE < .env
```

---

## 3. Local runner secret (`.secrets`)

When running locally with `act`, the runner needs a GitHub token for rate-limit
headroom and the `gh` CLI. Create `.secrets` (git-ignored):

```bash
cat > .secrets <<'EOF'
GITHUB_TOKEN=ghp_xxx          # repo, workflow, write:packages, delete:packages
EOF
```

`tools/ci/act-runner/act-runner.sh` sources `.secrets` and passes
`GITHUB_TOKEN` separately from `ENV_FILE`.

---

## 4. Prepare the startup images

### `zot-cache` (automatic)

The Zot registry-cache image is pulled and imported into Incus **automatically**
by the `zot_cache` Terraform module during `apply` (via `incus image copy` from
the ghcr OCI remote, idempotent — skipped if the `zot-cache` alias already
exists). There is no destroy provisioner, so the image survives
`terraform destroy` and is reused across destroy/apply cycles. No manual step is
required before `act-stage-base`.

### Talos VM image (automatic)

The Talos image (`talos-<version>-drbd`, e.g. `talos-1.11.2-drbd`) is
downloaded from the Talos release and imported into Incus **automatically** by
the `incus` Terraform module during `apply` — no manual step is needed.

---

## 5. Preflight check

Run the readiness check before kicking off any pipeline:

```bash
make preflight
# => tools/ci/preflight.sh
```

It verifies, and must report **0 failures, 0 warnings**:

- **Binaries** — every tool in `REQUIREMENTS.md` (Local CLI Tooling) is present.
- **Daemons** — Docker and Incus are reachable.
- **Images** — the `zot-cache` Incus alias is created automatically by
  Terraform during `apply` (no manual step needed).
- **Config** — `.env` exists with the required `ATLAS_CA_CRT_B64` /
  `ATLAS_CA_KEY_B64` pair (and the other Vault/cosign seeds); `.secrets`
  contains `GITHUB_TOKEN`.
- **Network** — no external interface already owns `10.200.10.0/24` (Talos
  control-plane / LB pool). If a cluster is already bootstrapped here, this is
  expected and reported as INFO.
- **Connectivity** — `ghcr.io` is reachable (Seal image pull).
- **Resources** — minimum **8 GB RAM** to run at all (hard floor); **12 GB**
  recommended for the base layer (3 nodes: argocd, linstor, vault, gateway,
  eso); **~32 GB RAM** for a full all-layers run.

Fix any reported failure (most commonly: populate the
missing `.env` / CA values) and re-run until clean.

---

## 6. Next: bootstrap the cluster

With preflight green:

```bash
make act-build            # build the act-runner image (once)
make act-ci               # full pipeline: base + middleware + workload
```

Or stage by stage:

```bash
make act-stage-base       # infra (Incus/Talos) + Vault seeds
make act-stage-middleware # platform layers (DB/MinIO/Vault/monitoring)
make act-stage-workload   # seed + sync workloads (seal)
```

> Note: after `act-stage-base` the in-cluster Vault must be initialized and
> unsealed, and the `vault-unseal-keys` secret (holding `vault-root`) must
> exist before the `seed-vault` step can write secrets. This is a manual
> operator step not performed by the pipeline.
