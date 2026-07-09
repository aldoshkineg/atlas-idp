# Cosign — Image Signing & Verification

This document describes how container images for the Seal project
(`ghcr.io/aldoshkineg/seal-api`, `ghcr.io/aldoshkineg/seal-worker`,
`ghcr.io/aldoshkineg/seal-ui`) are signed and verified in Atlas IDP.

We use a **simple key-pair** (no CA, no keyless/OIDC). Only our own images
are signed and verified; third-party images (Grafana, Loki, etc.) are **not**
checked by Kyverno.

## Overview

| Artifact          | Location                                          | Status    |
| ----------------- | ------------------------------------------------- | --------- |
| `cosign.pub`      | `security/cosign/cosign.pub` (committed)         | public    |
| `cosign.key`      | GitHub Secret `COSIGN_PRIVATE_KEY` (git-ignored) | private   |
| `COSIGN_PASSWORD` | empty (key has no passphrase)                    | —         |

Flow:

```
dev → push image → CI: cosign sign --key env://COSIGN_PRIVATE_KEY
                                    │
                                    ▼
                             GHCR (image + signature)
                                    │
        verify : cosign verify --key security/cosign/cosign.pub   (local / CI)
        enforce: Kyverno require-image-signature                  (in-cluster)
```

## Key generation

Keys are already generated and placed (see below). To regenerate:

```sh
cosign generate-key-pair --output-key-prefix security/cosign/cosign
# leave the passphrase empty (press Enter twice)
```

This creates:

- `security/cosign/cosign.key` — private key (**not committed**, listed in `.gitignore`)
- `security/cosign/cosign.pub` — public key (committed)

> **Empty passphrase is required.** cosign's `generate-key-pair` reads the
> passphrase from a TTY, so it must be generated in an interactive shell (or
> via a pseudo-TTY) to end up with an empty passphrase. A key generated
> non-interactively without a TTY will get a random passphrase and CI signing
> will fail with `decrypt: encrypted: decryption failed`.

Upload the private key to GitHub Secrets (raw PEM, with newlines — **not**
base64, because cosign reads it via `env://COSIGN_PRIVATE_KEY`):

```sh
gh secret set COSIGN_PRIVATE_KEY < security/cosign/cosign.key
```

## Signing in CI

`.github/workflows/seal-docker-publish.yml` builds and pushes images in a
matrix over the services (`seal-api`, `seal-worker`, `seal-ui`) and tags.
After the `docker/build-push-action` step, a signing step is added:

```yaml
- name: Install cosign
  uses: sigstore/cosign-installer@v3

- name: Sign image with cosign
  env:
    COSIGN_PASSWORD: ""
    COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
  run: |
    for img in $(echo "${{ steps.meta.outputs.tags }}" | tr '\n' ' '); do
      cosign sign --yes --key env://COSIGN_PRIVATE_KEY "${img}"
    done
```

**Trigger:** the workflow runs only on push of a `v*` tag or via
`workflow_dispatch` (manual run). Pushing to `main` does **not** build or sign
images. Every tag emitted by `docker/metadata-action` (`type=ref,event=tag`
for `v*` tags, plus a dev tag on `workflow_dispatch`) is signed.

> The GitHub Secret `COSIGN_PRIVATE_KEY` must contain the **unencrypted** key
> matching `security/cosign/cosign.pub`. If CI fails with
> `decrypt: encrypted: decryption failed`, the secret holds a key encrypted
> with a real passphrase — regenerate with an empty passphrase and re-set it.

## Local signing

`apps/seal/Taskfile.yml` provides local signing:

- `push-images` — pushes images and signs them afterwards.
- `sign-images` — signs already-pushed images, reading the key from
  `$COSIGN_PRIVATE_KEY` (skipped gracefully if the key is unset).

This keeps local pushes consistent with CI so they are also verifiable.

## Verification

Verify any image against the public key:

```sh
cosign verify --key security/cosign/cosign.pub \
  ghcr.io/aldoshkineg/seal-api:v0.52.0
```

A successful verification prints the signature JSON and exits 0. There is also
a `make` target:

```sh
make seal-verify TAG=v0.52.0
```

### Expected results

| Image                                  | Result                                                     |
| -------------------------------------- | ---------------------------------------------------------- |
| `seal-api:v0.52.0` (latest signed)    | ✅ verified against our public key                          |
| `seal-api:v0.25.0` (pre-cosign)       | ❌ `Error: no signatures found` (never signed)             |
| `janeczku/cosign-example:latest`      | ❌ `Error: no matching signatures ... did not match` (signed by another key) |

The last two rows are the expected failures: an unsigned image and an image
signed by someone else's key must **not** verify against our key.

## Enforcement (admission control)

Blocking unsigned images is performed by **Kyverno** in the cluster (the
`require-image-signature` ClusterPolicy), not by cosign itself. cosign only
**signs** and **verifies**; Kyverno **denies** deployment of
`ghcr.io/aldoshkineg/*` without a valid signature.

The policy embeds `security/cosign/cosign.pub` directly in its `verifyImages`
rule and runs in **`Enforce`** mode with deterministic settings:

```yaml
# gitops/platform/security/kyverno-policies/require-image-signature.yaml
spec:
  validationFailureAction: Enforce
  failurePolicy: Fail        # deny anything that cannot be verified
  rules:
    - name: verify-seal-images
      verifyImages:
        - imageReferences: ["ghcr.io/aldoshkineg/*"]
          mutateDigest: true   # resolve tag -> digest so signatures verify
          useCache: false      # resolve digest from registry (deterministic)
          verifyDigest: true
          required: true
          key: |-
            -----BEGIN PUBLIC KEY-----
            ... (contents of security/cosign/cosign.pub) ...
```

- **`failurePolicy: Fail`** — if an image cannot be verified (no signature,
  wrong key, or the registry is unreachable at admission), the pod is
  **denied**. This is what makes the control actually enforceable: an
  unverifiable image never reaches a node.
- **`useCache: false`** — Kyverno resolves the image digest directly from the
  registry instead of relying on the node image cache. This removes the
  dependency on whether some node already pulled the image, so verification is
  deterministic (a signed image is always verified; an unsigned one is always
  blocked) rather than flaky.
- **`mutateDigest: true`** — required for tag-based verification; only honoured
  in `Enforce` mode (in `Audit` it is forced `false` and digests cannot be
  resolved, so verification cannot run).

System namespaces (kyverno, argocd, kube-system, monitoring, loki, vault, …)
are excluded so platform components are not affected.

### Automated end-to-end check

`tests/scripts/cosign-kyverno-check.sh` exercises the whole chain against a
live cluster: Kyverno ready → all ClusterPolicies Ready → `cosign verify` of
the signed image (offline, against the repo public key) → valid signed image is
admitted and reported `PASS` by Kyverno → unsigned image is **rejected** at the
webhook.

```sh
KUBECONFIG=/var/tmp/atlas/talos/kubeconfig \
  bash tests/scripts/cosign-kyverno-check.sh
```

> After any key rotation, update the embedded public key in the Kyverno
> policy as well (see below).

## Key rotation

1. **Generate a new pair** (keep the old key available during the transition):
   ```sh
   mv security/cosign/cosign.key /tmp/cosign.key.old
   mv security/cosign/cosign.pub /tmp/cosign.pub.old
   cosign generate-key-pair --output-key-prefix security/cosign/cosign
   ```
2. **Update the GitHub Secret** with the new `cosign.key`:
   ```sh
   gh secret set COSIGN_PRIVATE_KEY < security/cosign/cosign.key
   ```
3. **Commit the new `cosign.pub`.**
4. **Update the embedded public key** in
   `gitops/platform/security/kyverno-policies/require-image-signature.yaml`
   (the `key:` field under `verifyImages`).
5. **Re-sign images** by pushing a new `v*` tag so CI signs them with the new
   key.
6. **Dual-key overlap (important):** until every running pod is on a
   newly-signed image, Kyverno must accept **both** the old and the new key,
   otherwise already-deployed pods on old (still-valid) images will be denied
   on the next reconcile. Add the old `cosign.pub` as a second `verifyImages`
   entry (or use `roots`) during the transition, then remove it once all
   workloads run images signed by the new key.
7. **Remove the old key** from the secret/policy once rotation is complete.

## Troubleshooting

- **`Error: no matching signatures`** — image is unsigned or signed by a
  different key. Confirm the CI `cosign sign` step ran and the tag matches.
- **`Error: no signatures found`** — the image has no cosign signature at all
  (e.g. an image built before signing was introduced).
- **`decrypt: encrypted: decryption failed`** — the `COSIGN_PRIVATE_KEY` secret
  holds a key encrypted with a real passphrase, but `COSIGN_PASSWORD` is empty.
  Regenerate the key with an **empty** passphrase and re-set the secret.
- **`key not found` / empty key** — `COSIGN_PRIVATE_KEY` is missing from repo
  secrets, or contains base64 instead of raw PEM.
- **`detect-private-key` pre-commit failure** — `cosign.key` was staged. Ensure
  it stays in `.gitignore` (`security/cosign/cosign.key`).
- **Signature rejected by Kyverno** — verify the public key embedded in the
  policy matches `security/cosign/cosign.pub`, and that the deployed image tag
  is exactly the one that was signed.
- **Kyverno reports `no signatures found` for an image you signed locally** —
  a manual `docker pull` + `docker tag` + `docker push` of an existing image
  creates a docker-media-type manifest while `cosign sign` attaches the
  signature to the OCI equivalent manifest. Kyverno resolves the tag to the
  docker digest and finds no signature. **Always sign via CI** (`seal-docker-publish.yml`
  on a `v*` tag) which keeps the manifest and signature consistent; never
  re-tag-and-push an already-built image by hand.
- **Valid image admitted but no `PASS` PolicyReport (or flaky verification)** —
  caused by `failurePolicy: Ignore` + `useCache: true`: when the image digest
  is not yet in the node image cache, Kyverno cannot verify and silently admits
  the pod unverified. Use `failurePolicy: Fail` + `useCache: false` so
  verification is deterministic.
