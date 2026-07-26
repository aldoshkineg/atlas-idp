# Atlas IDP — Technology & Tooling Inventory

> Inventory of every technology and program used in the project, with notes on
> what each one proves at a senior Platform Engineer level. Items marked
> **[key]** carry the most portfolio value — they differentiate this project
> from a tutorial and should be emphasized in interviews.

---

## Infrastructure as Code & Provisioning

| Technology           | Role                                                      | Senior value                                                                                                                                                                                                         |
| -------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OpenTofu / Terraform | Modular IaC; cluster + Argo CD bootstrap                  | Environment-scoped, reusable modules, `versions.tf` discipline                                                                                                                                                       |
| Talos Linux          | Immutable Kubernetes OS on bare metal                     | **[key]** real HA control plane (floating VIP `10.200.10.10`, Talos-native) — [how the CP VIP works](cluster-internals.md#0-control-plane-vip-talos--the-cluster-api-endpoint), disk/OS/bootstrap ops vs managed k8s |
| Incus                | VM hypervisor hosting Talos nodes                         | **[key]** bare-metal-class execution, no cloud account needed                                                                                                                                                        |
| Zot (OCI cache)      | Pull-through registry mirror (Terraform-managed in Incus) | **[key]** registry mirroring / air-gap: image supply-chain control + offline resilience                                                                                                                              |

CLIs: `tofu`/`terraform`, `talosctl`, `incus`.

---

## Kubernetes Runtime & Networking

| Technology         | Role                                                 | Senior value                                                                                                                                                                                          |
| ------------------ | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Kubernetes (Talos) | Cluster runtime                                      | CKA-level operating model                                                                                                                                                                             |
| Cilium (eBPF)      | CNI, LoadBalancer IPAM, Gateway API, netpols, Hubble | **[key]** single eBPF dataplane collapses CNI+LB+Ingress+network policy (+ Hubble network observability) — [how LB/VIP works](cluster-internals.md#1-load-balancing--vip-cilium-no-cloud--no-metallb) |
| Gateway API        | Ingress via Cilium GatewayClass                      | Standards-based ingress, not vendor lock-in                                                                                                                                                           |
| metrics-server     | Resource metrics for HPA                             | Autoscaling foundation                                                                                                                                                                                |

CLIs: `kubectl`, `cilium`.

---

## GitOps & Delivery

| Technology    | Role                                            | Senior value                                                                |
| ------------- | ----------------------------------------------- | --------------------------------------------------------------------------- |
| Argo CD       | App-of-apps, declarative single source of truth | **[key]** dependency-ordered bootstrap (`depends-on`), multi-layer platform |
| Argo Rollouts | Canary / progressive delivery                   | **[key]** delivery modeled as a platform primitive, not per-service         |

CLIs: `argocd`.

---

## Secrets Management

| Technology                | Role                           | Senior value                                |
| ------------------------- | ------------------------------ | ------------------------------------------- |
| HashiCorp Vault           | Central secret store, K8s auth | **[key]** enterprise secret-operating model |
| External Secrets Operator | Syncs Vault → K8s secrets      | References, never commits, secrets          |

CLIs: `vault`.

---

## Storage, Data & Backup

| Technology     | Role                                        | Senior value                                                                                                                                   |
| -------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Linstor (DRBD) | Replicated block storage CSI                | **[key]** real pod HA on bare metal, no cloud volumes — [how CSI works](cluster-internals.md#2-csi--replicated-storage-linstor--piraeus--drbd) |
| CloudNativePG  | Postgres operator + backups                 | **[key]** production DB ops, PITR/backup lifecycle                                                                                             |
| MinIO          | S3-compatible object store (Velero backend) | Self-hosted S3, avoids cloud object storage                                                                                                    |
| Velero         | Cluster backup / DR                         | **[key]** DR that is _exercised_ (restore tests)                                                                                               |
| Redis          | Cache / KEDA broker                         | Event source for autoscaling                                                                                                                   |

---

## Autoscaling

| Technology | Role                                         | Senior value                                    |
| ---------- | -------------------------------------------- | ----------------------------------------------- |
| KEDA       | Event-driven autoscaling (Redis list scaler) | **[key]** scaling on real signals, not just CPU |
| HPA        | CPU/memory autoscaling                       | Baseline elasticity                             |

---

## Observability

| Technology            | Role                                | Senior value                                    |
| --------------------- | ----------------------------------- | ----------------------------------------------- |
| kube-prometheus-stack | Prometheus + Grafana + Alertmanager | **[key]** alert rules, dashboards, SLO thinking |
| Loki                  | Log aggregation                     | Unified logging layer                           |
| Grafana Tempo         | Distributed tracing backend         | Full metrics/logs/traces triad                  |
| Grafana Alloy         | OTEL collector (OTLP → Tempo)       | Unified telemetry pipeline                      |

CLIs: `promtool` (implicit), Grafana UI.

---

## Security Baseline

| Technology                 | Role                                           | Senior value                                                                                                                                |
| -------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| cert-manager               | Issuing/rotating TLS certs                     | Automated PKI                                                                                                                               |
| Trivy                      | Image & IaC scanning (HIGH/CRITICAL gate)      | Shift-left security in CI                                                                                                                   |
| Cosign                     | Image signing (keys in `security/cosign`)      | Supply-chain integrity                                                                                                                      |
| Kyverno                    | Policy engine: PSS-like + image-signature gate | **[key]** admission governance; `require-image-signature` verifies Cosign, plus `disallow-privileged` / `run-as-non-root` / `no-latest-tag` |
| CiliumNetworkPolicy / CCNP | L3-L7 network isolation                        | **[key]** zero-trust pod networking                                                                                                         |
| RBAC                       | Kubernetes authorization                       | Least-privilege platform access                                                                                                             |

---

## CI/CD & Quality Gates

| Technology     | Role                                            | Senior value                                |
| -------------- | ----------------------------------------------- | ------------------------------------------- |
| GitHub Actions | Terraform validate, yamllint, Trivy, pre-commit | Pipeline-as-code, multi-stage quality gates |
| act            | Run GH Actions locally (env apply/sync)         | Reproducible local CI                       |
| pre-commit     | Hooks: fmt, yaml, trivy, terraform docs         | Enforced quality before commit              |
| yamllint       | YAML lint (140-col, document-start off)         | Lint discipline                             |

---

## Developer Experience (the IDP surface)

| Technology                               | Role                                     | Senior value                                            |
| ---------------------------------------- | ---------------------------------------- | ------------------------------------------------------- |
| `atlasctl` (Go)                          | CLI for workload lifecycle management    | **[key]** self-service platform product, not just infra |
| Golden-path templates (`templates/gold`) | Scaffold workloads                       | **[key]** paved roads / golden paths for tenants        |
| Helm                                     | Packaging for `seal` and platform charts | Chart authoring, values layering                        |

---

## Sample Workload

| Technology  | Role                                            | Senior value                                                                                                                        |
| ----------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `seal` (Go) | Reference app: api + worker + ui, Helm-packaged | **[key]** multi-service app with probes, limits, KEDA worker, Rollouts, plus logging/metrics/tracing wired to Loki/Prometheus/Tempo |
| Redis       | Broker for `seal` worker scaling                | End-to-end event-driven demo                                                                                                        |

---

## Languages & Formats

- **Go** — `atlasctl`, `seal` (api/worker/ui)
- **HCL** — Terraform/OpenTofu modules
- **YAML** — GitOps, Kubernetes, CI
- **Bash** — bootstrap/test scripts
- **Helm (Go templates)** — chart packaging

---

## Highest-Value Highlights (interview cheat-sheet)

1. **Cilium eBPF** — one dataplane for networking, LB, Gateway, netpols.
2. **Linstor (DRBD)** — replicated HA storage on bare metal, no cloud volumes.
3. **Talos + Incus** — immutable OS, real HA control plane, no managed cloud.
4. **Argo CD app-of-apps + Rollouts** — layered, dependency-ordered, canary delivery.
5. **Vault + External Secrets** — enterprise secret model, nothing committed.
6. **KEDA** — event-driven autoscaling on a real Redis broker.
7. **Velero + CloudNativePG DR** — disaster recovery that is actually tested.
8. **`atlasctl` + golden paths** — the developer-facing product of the IDP.
9. **Cosign + Trivy + Kyverno + netpols** — supply-chain and zero-trust baseline (Kyverno enforces Cosign signature verification at admission).
10. **Zot registry cache** — pull-through mirror / air-gap for image supply-chain control.
11. **Full observability triad** — Prometheus/Grafana (metrics) + Loki (logs) + Tempo (traces via Alloy/OTEL) + Hubble (network flows).
