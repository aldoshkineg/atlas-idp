# Architecture & Flow Diagrams

> Mermaid diagrams for the platform. GitHub renders these natively; they pair
> with `system-prompt.md` and `tech-stack.md` as the visual layer of the CV
> showcase.

---

## 1. Infrastructure & Deployment Topology

```mermaid
flowchart TB
  CI[CI: act / self-hosted runner]
  TF[Terraform / OpenTofu: Talos, Incus VMs, Cilium CNI]
  subgraph ARGO["Argo CD — App-of-Apps"]
    direction TB
    BASE[base: LINSTOR, Vault, ESO]
    MID[middleware: monitoring, security, delivery]
    WL[workloads: developer projects]
    BASE --> MID --> WL
  end
  CI --> ARGO
  TF --> ARGO
```

---

## 2. CI/CD Pipeline

```mermaid
flowchart LR
  A[Push / PR] --> B[ci-base: tools + Terraform (Incus/Talos) + Argo CD bootstrap + Vault seeds]
  B --> C[ci-middleware: sync platform layers (base/storage/security/delivery/observability)]
  C --> D[ci-workload: seed + sync tenant workloads (seal)]
  D --> E[make test: platform e2e suites]
  B -.fail-fast.-> X[ci-destroy on error]
```

Run locally via `act` on a self-hosted runner; phases are `act-stage-base`,
`act-stage-middleware`, `act-stage-workload`.

---

## 3. Secrets Flow (Vault → External Secrets → Workload)

```mermaid
flowchart TB
  VB[Vault (tools/vault bootstrap)] -->|Kubernetes auth| VA[VaultAuth / VaultAuthMethod]
  VA -->|issuses short-lived token| ESO[External Secrets Operator]
  ESO -->|sync| ES[ExternalSecret]
  ES -->|creates| KS[Kubernetes Secret]
  KS -->|mounted / env| P[seal pods]
  KYV[Kyverno: require-image-signature] -.admission gate.-> P
```

Nothing secret is committed; images must be Cosign-signed and are verified at
admission by Kyverno.

---

## 4. Network Flow (Ingress → Service → Backend)

```mermaid
flowchart LR
  U[User / *.atlas] -->|DNS| GW[Cilium Gateway VIP 10.200.10.100]
  GW --> R[HTTPRoute / Gateway API]
  R --> SVC[seal-api Service]
  SVC --> P[seal-api pods]
  P -->|Redis list| W[seal-worker]
  P -->|Postgres| PG[(CloudNativePG)]
  P -->|S3| MINIO[(MinIO)]
  NP[CiliumNetworkPolicy / CCNP] -.restricts east-west.-> P
  NP -.-> W
```

The VIP is announced by Cilium LB IPAM via L2 (ARP); no cloud LB / MetalLB.

---

## 5. Observability Stack

```mermaid
flowchart TB
  W[Workloads] -->|metrics| PROM[Prometheus]
  W -->|logs| ALLOY[Grafana Alloy]
  W -->|OTLP traces| ALLOY
  ALLOY --> LOKI[Loki]
  ALLOY --> TEMPO[Tempo]
  PROM --> AM[Alertmanager]
  PROM --> GRAF[Grafana]
  LOKI --> GRAF
  TEMPO --> GRAF
  HUB[Cilium Hubble] --> GRAF
```

---

## 6. Workload Onboarding (self-service sequence)

```mermaid
sequenceDiagram
  participant Dev
  participant Atlasctl
  participant Git
  participant ArgoCD
  participant K8s
  Dev->>Atlasctl: atlasctl new shop/orders
  Atlasctl->>Git: scaffold from templates/gold (PR)
  Dev->>Git: merge
  Git->>ArgoCD: detect change (app-of-apps)
  ArgoCD->>K8s: apply AppProject + Application
  K8s->>K8s: Helm install, Argo Rollouts canary, KEDA autoscale
  K8s->>Vault: ExternalSecret sync (via ESO)
```
