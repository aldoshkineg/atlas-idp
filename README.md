# Atlas IDP

**Internal Developer Platform — GitOps-driven Kubernetes platform engineering on self-hosted infrastructure**

![License](https://img.shields.io/badge/license-MIT-green)
![IaC](https://img.shields.io/badge/IaC-Terraform%20%2F%20OpenTofu-7B42BC)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.34-326CE5)
![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-EF7B4D)
![CNI](https://img.shields.io/badge/CNI-Cilium%20eBPF-F5A623)
![Secrets](https://img.shields.io/badge/Secrets-HashiCorp%20Vault-000000)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF)
![Observability](https://img.shields.io/badge/Observability-Prometheus%20%2F%20Grafana%20%2F%20Loki-FF6C37)

**Atlas IDP** is an end-to-end Internal Developer Platform that codifies production-grade platform-engineering patterns — Infrastructure as Code, GitOps delivery, progressive delivery, L2/L3 load balancing, policy-as-code, supply-chain security, secrets management, backups and disaster recovery, observability — on a self-hosted **Talos Linux** Kubernetes cluster (Incus VMs). The platform is managed and applications from development teams are launched with **atlasctl**, a Go CLI. A reference example is **seal**, a Helm-packaged microservice (API + UI + worker) with structured logging and OpenTelemetry tracing.

## Table of Contents

- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Access the platform](#access-the-platform)
- [Testing](#testing)
- [Workflow (Makefile Targets)](#workflow-makefile-targets)
- [CI/CD Pipeline](#cicd-pipeline)
- [Atlasctl](#atlasctl)
- [Example Workload](#example-workload)
- [Security & Policy](#security--policy)
- [Observability](#observability)
- [Roadmap](#roadmap)
- [License](#license)

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Atlasctl - Platform Management Tool                   │
│                             Workload Lifecycle:                              │
│    new / enable / disable / seed / delete / status / list / logs / backup    │
└──────────────────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CI/CD - GitHub Actions                              │
│                    Act or Cloud runner / Self-hosted                         │
│               ci: ci-base -> ci-middleware -> ci-workload                    │
│                          build: atlasctl, seal                               │
└──────────────────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────────────────────────────────────────────┐
│                               GitOps - Argo CD                               │
│           Layers: base / security / storage / delivery / observability       │
└──────────────────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  Workloads                                   │
│                        Seal (Example Microservice App)                       │
│              seal-api / seal-ui / seal-worker / dlq CronJob                  │
└──────────────────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────────────────────────────────────────────┐
│                       Kubernetes Runtime - Talos Linux                       │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │Cilium      │ │LB (Cilium) │ │Gateway     │ │Argo        │ │Kyverno     │  │
│  │CNI         │ │IPPool      │ │Envoy       │ │Rollouts    │ │(Policy)    │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │Vault +     │ │KEDA +      │ │LINSTOR     │ │CNPG        │ │MinIO       │  │
│  │ESO         │ │Metrics     │ │Storage     │ │PG+Redis    │ │(S3)        │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │Velero      │ │Trivy       │ │Cosign      │ │Snapshot    │ │cert-manager│  │
│  │(DR)        │ │Operator    │ │Sign        │ │(Ctrl)      │ │(TLS)       │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
│               Observability:  Prometheus / Grafana / Alertmanager            │
│                   Loki / Tempo / Grafana Alloy / Hubble                      │
└──────────────────────────────────────────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────────────────────────────────────────────┐
│                    Infrastructure - Terraform / OpenTofu                     │
│                             Incus / Talos VMs                                │
│                       ┌────────────┐                                         │
│                       │VIP (HA)    │                                         │
│                       │10.200.10.10│                                         │
│                       └────────────┘                                         │
│                          │  to CP nodes                                      │
│      ┌──────────────────────┐ ┌──────────────────────┐ ┌────────────┐        │
│      │    Control planes    │ │    Workers           │ │ Zot cache  │        │
│      │┌────────┐ ┌────────┐ │ │┌────────┐ ┌────────┐ │ │   images   │        │
│      ││cp-1    │ │cp-n    │ │ ││worker-1│ │worker-n│ │ └────────────┘        │
│      └──────────────────────┘ └──────────────────────┘                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

> More diagrams — secrets, network, CI/CD and observability flows:
> [`docs/cv/diagrams.md`](docs/cv/diagrams.md).

## Tech Stack

```text
┌──────────────────────────┬────────────────────────────────────────────────────────────────┐
│        Capability        │                        Tools we provide                        │
├──────────────────────────┼────────────────────────────────────────────────────────────────┤
│Infrastructure as Code    │Terraform, OpenTofu                                             │
│Virtualization / Host     │Incus (local VMs)                                               │
│OS / Kubernetes           │Talos Linux, Kubernetes v1.34                                   │
│CSI / Storage             │LINSTOR / Piraeus (replicated block, DRBD), snapshot-controller │
│CNI + Networking (eBPF)   │Cilium - CNI, kube-proxy-less, Gateway API, L2/L3 LB, network   │
│                          │policies, Hubble                                                │
│GitOps                    │Argo CD (App-of-Apps), Argo Rollouts (canary / progressive      │
│                          │delivery)                                                       │
│CI/CD                     │GitHub Actions (self-hosted runner), act                        │
│Secrets Management        │HashiCorp Vault, External Secrets Operator (ESO)                │
│Policy-as-Code            │Kyverno (admission / policy), Cosign image verification         │
│Supply-Chain Security     │Cosign (image signing), Trivy / Trivy Operator (scanning)       │
│TLS / PKI                 │cert-manager (issuing / rotating TLS)                           │
│Observability             │Prometheus, Grafana, Alertmanager, Loki, Tempo, Grafana Alloy,  │
│                          │Hubble                                                          │
│Databases                 │CloudNativePG (PostgreSQL), Redis (HA)                          │
│Object Storage            │MinIO (S3-compatible)                                           │
│Autoscaling               │KEDA (event-driven), metrics-server (HPA)                       │
│Backup / DR               │Velero, CloudNativePG (Barman → MinIO/S3)                       │
│Platform Tooling          │atlasctl (Go CLI - golden-path workload onboarding)             │
│Sample Workload           │seal - api / ui / worker / dlq CronJob (Helm-packaged)          │
│Registry Cache            │Zot (OCI registry cache / pull-through mirror)                  │
│Languages                 │Go, HCL, YAML, Shell                                            │
└──────────────────────────┴────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
atlas-idp/
├── apps/                       # Application source + Helm charts
│   └── seal/                   #   Sample tenant workload (API/UI/worker) + chart
├── gitops/                     # GitOps manifests (Argo CD)
│   ├── platform/
│   │   ├── layers/             #   Layer Applications (base/security/storage/…)
│   │   ├── base/               #   Cilium Gateway, routes, network policies, cert issuers
│   │   ├── storage/            #   Piraeus/LINSTOR, snapshot controller, CNPG, MinIO, Redis
│   │   ├── security/           #   Kyverno (+ policies), Vault operator, ESO, Trivy
│   │   ├── delivery/           #   Argo Rollouts, KEDA, metrics-server
│   │   └── observability/      #   kube-prometheus-stack, Loki, Tempo, Alloy
│   └── workloads/              #   Tenant workload Applications (atlasteam/seal)
├── workloads/                  # Per-tenant workload definitions (atlasctl registry)
│   └── atlasteam/seal/         #   app.yaml, infra, vault policy, monitoring
├── infra/                      # Infrastructure as Code (Terraform/OpenTofu)
│   ├── environments/           #   stage (Incus/Talos, active)
│   └── modules/                #   Reusable modules
├── security/                   # CA certs, RBAC, Trivy, Cosign keys
├── tools/                      # Utils and tools
│   └── atlasctl/               #   atlasctl (Go CLI)
├── tests/                      # Platform smoke/integration tests (make test)
├── templates/                  # Golden-path workload templates (atlasctl scaffold source)
├── recipes/                    # Cluster snippets (standalone kubectl apply, outside GitOps)
├── docs/                       # Documentation
├── Makefile                    # Developer + CI workflow targets
├── .pre-commit-config.yaml     # Pre-commit hooks
└── .yamllint.yml               # YAML linting rules
```

See [`docs/cv/system-prompt.md`](docs/cv/system-prompt.md) for the engineering narrative, or [`docs/setup.md`](docs/setup.md) for the full getting-started guide. Operational runbooks live under [`docs/runbooks/`](docs/runbooks/).

---

## Quick Start

### Prerequisites

- [Incus](https://linuxcontainers.org/incus/) (local VM host for Talos nodes)
- [Terraform](https://www.terraform.io/) / [OpenTofu](https://opentofu.org/) v1.9+
- [talosctl](https://www.talos.dev/) and [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.31+
- [Docker](https://www.docker.com/) (for the CI runner / `act`)
- [Helm](https://helm.sh/), [Argo CD CLI](https://argo-cd.readthedocs.io/), [pre-commit](https://pre-commit.com/)

### 1. One-time Getting Started

To confirm the required tools are installed and variables/secrets are in place, run:

```bash
make preflight    # verify binaries, daemons, .env
```

See `docs/setup.md` for the full getting-started guide (tools, `.env`, CA, memory).

### 2. Minimal setup

Deployment runs through `act` (a local CI invocation). For the minimal set, run:

```bash
make act-stage-base         # Incus/Talos cluster + Argo CD + Vault seeds
```

### 3. Full deployment

For a full, production-like deployment with sample app, run:

```bash
make act-build          # build the local CI runner image (once) with pre-baked tooling
make act-ci             # ci-all: base ▶ middleware ▶ workloads
```

### 4. Tear down

```bash
make act-destroy    # destroy the stage infrastructure
make act-destroy-force  # hard teardown: kill all VMs and remove Terraform state files
```

---

## Access the platform

Services are exposed through the Cilium Gateway (TLS via cert-manager). Map the
gateway LoadBalancer IP to the `*.atlas` hostnames in `/etc/hosts`, then:

| Service       | URL                        |
| ------------- | -------------------------- |
| Argo CD       | `https://argocd.atlas`     |
| Grafana       | `https://grafana.atlas`    |
| Vault         | `https://vault.atlas`      |
| MinIO (S3)    | `https://s3.atlas`         |
| MinIO console | `https://console.s3.atlas` |
| Seal          | `https://seal.atlas`       |

---

## Testing

`make test` runs the platform smoke/integration suite (`tests/scripts/`); the same set is executed by the `test-platform.yaml` workflow:

| Test                  | Verifies                                        |
| --------------------- | ----------------------------------------------- |
| `test-ca-gateway`     | Gateway API TLS termination end-to-end          |
| `test-vault`          | Vault seeding + secret injection                |
| `test-network-policy` | NetworkPolicy isolation                         |
| `test-velero`         | Velero backup/restore to S3                     |
| `test-keda`           | KEDA autoscaling                                |
| `test-redis`          | Redis connectivity/auth                         |
| `test-db-backup`      | CloudNativePG backup/restore to MinIO           |
| `test-argocd-rollout` | Argo Rollouts canary progression                |
| `test-seal`           | seal end-to-end (pods, API, documents, gateway) |

---

## Workflow (Makefile Targets)

The Makefile is a thin task dispatcher: every target delegates to a script under
`tools/` and is **self-documenting**. Run `make` (or `make help`) to print the
full, grouped target list with descriptions and required arguments.

> The active workflow is Incus/Talos via the `act-*` and `ci-runner-*` targets.

---

## CI/CD Pipeline

CI runs as GitHub Actions workflows (`.github/workflows/`): `ci-all` and the
security, unit-test and release workflows trigger automatically on push,
pull_request and tags, while the stage pipelines (`ci-base` / `ci-middleware` /
`ci-workload` / `ci-destroy` / `ci-destroy-force`) and `test-platform` can also
be launched manually via `workflow_dispatch`. The stage workflows are reusable
building blocks called by `ci-all` through `workflow_call`. The cluster persists
after a run (no auto-destroy). Locally, the equivalent is `make act-ci` (full
run) or the staged `make act-stage-*` targets.

---

## Atlasctl

The `atlasctl` binary is published in the project's GitHub Releases:
<https://github.com/aldoshkineg/atlas-idp/releases>.

```sh
curl -Lo atlasctl -L "https://github.com/aldoshkineg/atlas-idp/releases/latest/download/atlasctl-linux-amd64"
chmod +x atlasctl
sudo mv atlasctl /usr/local/bin/
```

New workloads are onboarded with the `atlasctl` CLI: it scaffolds the workload
from templates, wires up a Gateway route, provisions Vault secrets and generates
the Argo CD Application:

```bash
atlasctl new   <team>/<name> --group <group> --repo <url> [--helm]  # scaffold
atlasctl enable <team>/<name> --force --sync                        # register + sync
atlasctl seed  <team>/<name>                                        # seed Vault secrets
atlasctl list                                                      # list workloads
```

> Locally the binary is built via `make atlasctl-build`; `make atlas-seal ARGS=<team>/<name>` is the same as `atlasctl seed`.

---

## Example Workload

**seal** is the platform's reference tenant workload — a Helm-packaged microservice whose images are published to GHCR (public):

- [![seal-api](https://img.shields.io/badge/seal--api-ghcr.io-blue)](https://ghcr.io/aldoshkineg/seal-api) — REST API (CloudNativePG, Redis, MinIO, OTel → Tempo)
- [![seal-ui](https://img.shields.io/badge/seal--ui-ghcr.io-blue)](https://ghcr.io/aldoshkineg/seal-ui) — web UI
- [![seal-worker](https://img.shields.io/badge/seal--worker-ghcr.io-blue)](https://ghcr.io/aldoshkineg/seal-worker) — worker + DLQ CronJob

All images are Cosign-signed and verified by Kyverno at admission. Source & chart: [`apps/seal`](apps/seal); all tags in [Packages](https://github.com/aldoshkineg/atlas-idp/packages).

The bundled **seal** workload (`apps/seal`, `workloads/atlasteam/seal`) is the
reference implementation: PostgreSQL (CloudNativePG) + Redis + MinIO, Argo
Rollouts canary, KEDA autoscaling, ExternalSecrets from Vault, a DLQ CronJob,
ServiceMonitors/alerts, OTel traces to Tempo, and a Cosign-signed image enforced
by Kyverno.

---

## Security & Policy

- **Policy-as-code (Kyverno):** disallow `:latest`, disallow privileged/hostPath,
  require non-root, require standard labels, and **enforce Cosign image
  signatures** on tenant images.
- **Secrets:** HashiCorp Vault as the source of truth; External Secrets Operator
  syncs secrets into namespaces via a `vault` ClusterSecretStore.
- **Runtime scanning:** Trivy Operator scans workloads for vulnerabilities.
- **Supply chain:** container images are signed with Cosign and verified at
  admission.
- **TLS:** cert-manager issues certificates from an internal CA for all Gateway
  listeners.
- **Pre-commit:** trailing whitespace / EOF / YAML checks, merge-conflict &
  private-key detection, `terraform fmt/validate`, yamllint, kubeconform, Trivy,
  secret detection.

---

## Observability

- **Metrics:** kube-prometheus-stack (Prometheus + Alertmanager) with recording
  and alerting rules, including platform availability/capacity rules and
  per-workload alerts (e.g. `seal-alerts`).
- **Logs:** Loki + Grafana Alloy.
- **Traces:** Tempo (OpenTelemetry from workloads).
- **Dashboards:** Grafana (auto-provisioned).

---

## Roadmap

- **Multi-cluster / ClusterMesh** — stretch the platform across Talos clusters via Cilium ClusterMesh.
- **SSO** — OIDC (Dex/Keycloak) for Argo CD and Grafana.
- **Supply-chain attestations** — Sigstore/SLSA provenance verified in Kyverno.
- **Capacity & cost** — Kepler-based energy/cost reporting.
- **Multi-tenancy** — hierarchical namespaces + per-team quotas.
- **Docs site** — publish `docs/` as MkDocs Material / GitHub Pages.
- **CI e2e** — run `make test` on an ephemeral cluster in PRs.

---

## License

This project is open source and available under the [MIT License](LICENSE).
