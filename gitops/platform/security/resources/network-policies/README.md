# Networking Layer

This layer manages cluster networking: ingress gateways, HTTP routing, and network policies.

## Files

### Ingress & Routing

| File                     | Sync-wave | Purpose                                                                   |
| ------------------------ | --------- | ------------------------------------------------------------------------- |
| `gateway-api-crds.yaml`  | 1         | Installs Gateway API CRDs (GatewayClass, Gateway, HTTPRoute)              |
| _(cilium)_               | built-in  | Cilium Gateway API controller — cluster ingress gateway (in kube-system)  |
| `gateway-resources.yaml` | 5         | Gateway resource with TLS listeners for `*.atlas` domain                  |
| `gateway-routes.yaml`    | 7         | HTTPRoute rules mapping hosts to services (argocd, grafana, vault, minio) |

### Network Policies

| File          | Sync-wave | Purpose                                                  |
| ------------- | --------- | -------------------------------------------------------- |
| `netpol.yaml` | 10        | ArgoCD Application deploying all NetworkPolicy resources |

### Network Policy Definitions (`network-policies/`)

All policies are **CiliumNetworkPolicy**. Ingress is default-deny; each policy adds explicit allow rules. Two traffic classes are permitted in addition to pod-to-pod rules:

- **`fromEntities: [remote-node]`** — node-local traffic: kubelet health probes, kube-apiserver webhooks, cross-node pod traffic.
- **`fromEntities: [ingress]`** — traffic routed through the **Cilium Gateway API** (envoy upstream to backends). Cilium tags gateway-routed flows with the `reserved:ingress` (8) identity — **not** `world`.

> Note: earlier revisions documented `world` for external ingress. This is incorrect for the Cilium Gateway API — routed ingress traffic carries the `reserved:ingress` identity, so backend policies must allow `ingress`, not `world`.

Port columns show `any` unless restricted. Gateway-reachable backends additionally allow `ingress` (see table below).

| File                    | Namespace          | Allows inbound from                                                              | Ports      |
| ----------------------- | ------------------ | -------------------------------------------------------------------------------- | ---------- |
| `argocd.yaml`           | `argocd`           | same-namespace, kube-system, monitoring, **gateway (ingress)**                   | 80         |
| `vault.yaml`            | `vault`            | same-namespace, kube-system, external-secrets, monitoring, **gateway (ingress)** | 8200       |
| `external-secrets.yaml` | `external-secrets` | same-namespace, monitoring, argocd, kube-system                                  | any        |
| `monitoring.yaml`       | `monitoring`       | same-namespace, kube-system, **gateway (ingress)**                               | 80         |
| `loki.yaml`             | `loki`             | same-namespace, monitoring                                                       | 3100       |
| `minio.yaml`            | `minio`            | same-namespace, kube-system, database, velero, monitoring, **gateway (ingress)** | 9000, 9001 |
| `database.yaml`         | `database`         | same-namespace, cnpg-system, monitoring, **gateway (ingress)**                   | any        |
| `redis.yaml`            | `redis`            | same-namespace, keda, monitoring                                                 | 6379       |
| `cnpg-system.yaml`      | `cnpg-system`      | same-namespace, monitoring                                                       | any        |
| `kube-system.yaml`      | `kube-system`      | same-namespace, all-namespaces (DNS), monitoring                                 | 53/UDP+TCP |
| `velero.yaml`           | `velero`           | same-namespace, monitoring                                                       | any        |
| `keda.yaml`             | `keda`             | same-namespace, monitoring                                                       | any        |

## How Network Policies Work

Policies are defined as **CiliumNetworkPolicy** (CNP) resources. Each policy implements **default-deny ingress** with explicit allow rules:

```yaml
spec:
  endpointSelector: {} # applies to ALL pods in the namespace
  ingress:
    - fromEndpoints: # allows same-namespace traffic
        - matchLabels:
            io.kubernetes.pod.namespace: <ns>
    - fromEndpoints: # allows cross-namespace traffic
        - matchLabels:
            io.kubernetes.pod.namespace: <source-ns>
      toPorts:
        - ports:
            - port: "<N>"
              protocol: TCP
    - fromEntities: # allows node-local traffic (kubelet probes, API server webhooks, cross-node pods)
        - remote-node
    - fromEntities: # allows Cilium Gateway API ingress (envoy upstream to this backend)
        - ingress
```

Key behavior:

- **Implicit deny-all**: `endpointSelector: {}` with explicit ingress `from*` rules drops all inbound traffic that does not match. There is no separate "deny-all" resource.
- **Same-namespace allow**: every policy includes a `fromEndpoints` rule for its own namespace.
- **Monitoring allow (metrics + logs)**: every namespace with scrape targets allows inbound from `monitoring` on any port — Prometheus ServiceMonitors/PodMonitors discover endpoints dynamically, and Grafana reads from Prometheus. Log collection by Alloy is node-local (reads container stdout via the kubelet/CRI socket, not pod network), so it is unaffected by pod-level CNPs; Alloy→Loki push uses the `monitoring` allow rule.
- **Namespace-explicit allow**: service-to-service dependencies use `fromEndpoints` + `toPorts`.
- **Gateway ingress**: backend services exposed through the Cilium Gateway must allow `fromEntities: [ingress]`. Cilium Gateway API assigns the `reserved:ingress` (8) identity to routed traffic — this is distinct from `world` (raw external/NodePort) and from `remote-node`. Without `ingress`, envoy upstream connections to the backend are dropped.
- **Node-local traffic**: `remote-node` permits kubelet health probes and API server webhooks. Without it, probes/webhooks would be blocked.

## Traffic Flow Example

```
Internet → LoadBalancer IP (Cilium LB IPPool) / NodePort
  → Cilium Gateway API (envoy, external proxy, hostNetwork)
    → upstream to backend, tagged with reserved:ingress (8) identity
    → argocd-server.argocd.svc:80       ← allowed by argocd.yaml (ingress)
    → grafana.monitoring.svc:80         ← allowed by monitoring.yaml (ingress)
    → vault.vault.svc:8200              ← allowed by vault.yaml (ingress)
    → minio.minio.svc:9000              ← allowed by minio.yaml (ingress)

Prometheus (monitoring)
  → argocd:8082, vault:8200, minio:9000, ... ← allowed by each NS policy

seal-api (seal NS, deployed separately)
  → production-db-rw.database:5432      ← allowed by database.yaml
  → redis-master.redis:6379             ← allowed by redis.yaml
  → minio.minio:9000                    ← allowed by minio.yaml
```

## Namespaces Not Covered

- `cert-manager`: skipped — PodMonitor and ServiceMonitor are disabled; no inbound traffic expected
- `piraeus-datastore`: LINSTOR satellite pods communicate via host-network; no pod-to-pod inbound
- `seal`: deployed separately in `examples/`; namespace may not exist during platform bootstrap
- `default`: no platform workloads
