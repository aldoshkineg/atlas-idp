# Atlas IDP — System Design & Positioning Brief

> Audience: senior hiring panels (Platform Engineer / Cloud Architect / DevOps)
> Persona: senior Platform Engineer with Kubernetes expertise (CKA-level).
> This is a realistic, production-grade internal developer platform (IDP) — not a
> tutorial or lab. The document records the design intent and the realized system.

---

## 1. Context & Intent

The goal is to demonstrate, end-to-end, what a modern cloud-native platform team
operates: a self-service internal developer platform built GitOps-first, running
on **real bare-metal-class infrastructure** (not a managed cloud or a throwaway
kind cluster).

The engineer is experienced. The artifact must show:

- cloud-native architecture thinking
- Infrastructure as Code maturity (modular, environment-scoped)
- a GitOps operating model with progressive delivery
- observability and reliability engineering
- a minimal-but-real security posture
- CI/CD automation and disaster recovery

It must read as a system a senior engineer owns — trade-offs, dependency
ordering, and operational runbooks included.

### Deliberate deviations from the original design brief

The original brief assumed a `kind` cluster and GitLab CI. The realized system
intentionally diverges because it is more production-realistic:

| Original brief            | Realized decision              | Rationale                                           |
| ------------------------- | ------------------------------ | --------------------------------------------------- |
| kind (local k8s)          | Talos Linux on Incus VMs       | real bare-metal-class control plane, immutable OS   |
| GitLab CI                 | GitHub Actions                 | repo lives on GitHub; same pipeline intent          |
| cloud LB / Ingress NGINX  | Cilium (eBPF) Gateway API + LB | single eBPF dataplane: networking, LB, GW, netpols  |
| cloud block storage (EBS) | Linstor (DRBD) replicated CSI  | true HA storage on bare metal, no cloud dependency  |
| HPA only                  | KEDA + metrics-server          | event-driven autoscaling, not just CPU              |
| plain Deployments         | Argo Rollouts                  | progressive/canary delivery as a platform primitive |

Non-functional constraints still hold: no service mesh, no multi-cloud, no
Kafka — avoid overengineering. Clarity, production realism, and GitOps maturity
are the priority.

---

## 2. Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────────────┐
│  GitHub Repo    │────▶│  GitHub Actions │────▶│ Talos Kubernetes        │
│  (IaC + GitOps) │     │  (CI/CD)        │     │ (bare metal / Incus)    │
└─────────────────┘     └─────────────────┘     └─────────────────────────┘
                                                        │  Cilium (eBPF)
                                                        ▼  Linstor (HA storage)
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────────────┐
│  Terraform      │────▶│  Argo CD        │────▶│ Platform layers +        │
│  (infra/)       │     │  (app-of-apps)  │     │ tenant workloads         │
└─────────────────┘     └─────────────────┘     └─────────────────────────┘
```

Key properties:

- **Single source of truth**: everything declarative in git; no manual
  `kubectl apply` in the final model (manual recipes are quarantined under
  `recipes/` for bootstrapping only).
- **Layered platform**: base → security → storage → delivery, with explicit
  Argo CD `depends-on` ordering so bootstrap is deterministic.
- **Bare-metal HA**: control plane and workloads run on Talos nodes; storage is
  replicated via Linstor (DRBD) so pods survive node loss without a cloud.
- **Security baseline**: Vault-managed secrets via External Secrets Operator,
  Cilium cluster-wide network policies, image signing (Cosign), Trivy scanning,
  RBAC, cert-manager-issued TLS.

---

## 3. Tech Stack (realized)

| Domain           | Choice                                                                                                           |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| IaC              | OpenTofu / Terraform (modular, env-scoped)                                                                       |
| Runtime          | Talos Linux K8s on Incus VMs (bare metal class)                                                                  |
| Registry cache   | Zot pull-through mirror (air-gap / supply-chain)                                                                 |
| CNI / networking | Cilium (eBPF): Pod networking, LoadBalancer, GW API, CCNP                                                        |
| Ingress / GW     | Gateway API (Cilium Gateway)                                                                                     |
| Block storage    | Linstor (LINBIT DRBD) replicated CSI                                                                             |
| GitOps           | Argo CD (app-of-apps), Argo Rollouts (canary)                                                                    |
| Secrets          | HashiCorp Vault + External Secrets Operator                                                                      |
| Autoscaling      | KEDA (event-driven) + metrics-server / HPA                                                                       |
| Databases/cache  | CloudNativePG (Postgres), Redis, MinIO (S3)                                                                      |
| Observability    | kube-prometheus-stack (Prom + Grafana + alert rules), Loki, Tempo (traces), Alloy (OTEL), Hubble (network flows) |
| Backup / DR      | Velero → MinIO (on Linstor), CNPG backups                                                                        |
| CI/CD            | GitHub Actions (validate, yamllint, Trivy, pre-commit)                                                           |
| Security         | RBAC, Trivy, Cosign signing, Kyverno (admission + signature gate), Cilium netpols, cert-manager                  |
| Developer UX     | `atlasctl` CLI + golden-path templates (`templates/gold`)                                                        |

---

## 4. Layered System

1. **Infrastructure Layer** (`infra/`)
   Modular Terraform: Talos/Incus cluster provisioning, Argo CD bootstrap,
   environment abstraction (`environments/stage`). AWS-ready design notes kept
   where relevant, though execution is bare metal.

2. **GitOps Control Plane** (`gitops/bootstrap`, `gitops/platform`)
   Root Application (app-of-apps). Platform split into layers with dependency
   ordering: `base` (foundation: cert-manager, gateway-api, vault, linstor,
   external-secrets) → `security` (issuers, external-secrets, netpols, trivy)
   → `storage` (linstor, cnpg, postgres, redis, minio, velero, snapshots)
   → `delivery` (argo-rollouts, keda).

3. **Platform Services Layer**
   monitoring (Prometheus + Grafana + Loki), secrets (Vault + ESO),
   backup (Velero), progressive delivery (Argo Rollouts), event-driven
   scaling (KEDA).

4. **Workloads Layer** (`workloads/`, `apps/`)
   Tenant apps as single source of truth, scaffolded by `atlasctl` from
   golden-path templates. Reference app `seal`: backend API, KEDA-driven
   worker (Redis list scaler), probes, resource limits, canary rollout.

5. **CI/CD Layer** (`.github/`)
   Terraform validation, YAML lint, Trivy (HIGH/CRITICAL), pre-commit hooks,
   act-driven environment apply/sync.

6. **Developer Experience Layer** (`tools/atlasctl`, `templates/gold`)
   Self-service workload lifecycle and golden-path scaffolding — the
   "platform" surface developers actually touch.

---

## Reference Subprojects

- **tools/atlasctl** — the developer-facing surface of the IDP, a Go CLI that
  scaffolds tenant workloads from golden-path templates (`atlasctl new`) and
  drives their full GitOps lifecycle: `enable`/`disable` (Argo CD layer
  toggle), `seed` (Vault secrets), `backup`, `status`, `logs`. It turns
  "request a service" into a single self-service command.
- **apps/seal** — the reference workload that proves the platform end-to-end:
  a PDF signing/generation system (Go) with `seal-api` (REST), `seal-worker`
  (async CMS/PAdES signing off a Redis queue → MinIO), and `seal-ui` (HTMX),
  packaged as a Helm chart. On the cluster it exercises the platform primitives:
  Argo Rollouts canary, KEDA autoscaling on the Redis list, Gateway API ingress,
  CNPG/Redis/MinIO backends, ESO-managed secrets — and is fully observable:
  structured logging (Loki), Prometheus metrics, and OTLP tracing (Tempo via
  Alloy).

---

## 5. Repository Structure

```
infra/          Terraform modules + environments/stage + bootstrap
gitops/         Argo CD: bootstrap (root app), platform layers, workloads
workloads/      Tenant workload definitions (SSOT, atlasctl-managed)
templates/gold/ Golden-path templates (.tmpl) for scaffolding
recipes/        Manual kubectl snippets (bootstrap only, outside GitOps)
apps/           Source projects (e.g. seal): code, Helm chart, per-app tests
tools/vault/    Vault policies, K8s auth roles, bootstrap scripts
tools/atlasctl/ Go CLI for workload lifecycle management
security/       CA certs, RBAC, Trivy config, Cosign keys
tests/          Platform e2e suites + runners (gateway, keda, db-backup, velero)
.github/        GitHub Actions workflows and composite actions
docs/           ADRs, runbooks, component guides
```

---

## 6. Key Engineering Decisions & Trade-offs

- **Talos + Incus over kind/managed cloud**: immutable OS and a real HA control
  plane demonstrate bare-metal operations (disk, networking, bootstrap) that a
  managed cluster hides. Cost: higher operational complexity, justified for a
  platform-engineer portfolio.
- **Cilium as a single dataplane**: collapses CNI, LoadBalancer, Gateway, and
  network policy into one eBPF layer — less to operate, more coherent security
  story, vs. stitching Calico + MetalLB + NGINX.
- **Linstor for storage**: replicated block storage gives real pod HA on bare
  metal without cloud volumes; trades simplicity for production fidelity.
- **Argo CD dependency graph**: explicit `depends-on` makes bootstrap
  deterministic and debuggable (see `docs/runbooks/argocd-debugging.md`).
- **Vault + ESO, not sealed secrets**: follows enterprise secret-operating
  model; secrets are referenced, not committed.
- **KEDA + Rollouts**: autoscaling and delivery modeled as platform primitives
  consumed by tenant apps, not bespoke per-service config.

---

## 7. What Makes This "Senior-Level"

- Bare-metal HA: storage and networking that survive node loss without a cloud.
- Layered, dependency-ordered GitOps with progressive delivery.
- Event-driven autoscaling wired to a real broker (Redis).
- Disaster recovery that is _exercised_ (Velero + CNPG restore scenarios under
  `tests/`), not just configured.
- Developer self-service via CLI + golden paths — the actual product of an IDP.
- Operational artifacts: ADRs documenting decisions, runbooks for failure modes.
- Security baseline treated as a layer, not an afterthought.

---

## 8. CV Presentation (bullet points)

- Designed and operate a GitOps-driven internal developer platform on
  bare-metal Talos Kubernetes (Incus VMs), eliminating cloud lock-in.
- Replaced cloud networking/storage with Cilium (eBPF) and Linstor (DRBD)
  replicated CSI to deliver HA without managed services.
- Built a layered Argo CD app-of-apps platform (base/security/storage/delivery)
  with deterministic dependency-ordered bootstrap and Argo Rollouts canaries.
- Implemented Vault + External Secrets Operator as the platform secret model.
- Added event-driven autoscaling (KEDA) and progressive delivery as
  self-service primitives for tenant workloads.
- Established observability (Prometheus/Grafana/Loki) and tested DR (Velero,
  CNPG) with executed restore scenarios.
- Shipped developer self-service via an `atlasctl` Go CLI and golden-path
  templates; enforced quality with Trivy, Cosign, yamllint, and pre-commit.
