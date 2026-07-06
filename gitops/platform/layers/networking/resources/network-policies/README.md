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

All policies are **CiliumNetworkPolicy** and include `fromEntities: [remote-node, world]` to allow node and external traffic. Port columns show `any` unless restricted.

| File                    | Namespace          | Allows inbound from                                       | Ports      |
| ----------------------- | ------------------ | --------------------------------------------------------- | ---------- |
| `argocd.yaml`           | `argocd`           | same-namespace, kube-system, monitoring                   | 80         |
| `vault.yaml`            | `vault`            | same-namespace, kube-system, external-secrets, monitoring | 8200       |
| `external-secrets.yaml` | `external-secrets` | same-namespace, monitoring, argocd, kube-system           | any        |
| `nginx-gateway.yaml`    | `kube-system`      | cilium-agent, remote-node, world                          | any        |
| `monitoring.yaml`       | `monitoring`       | same-namespace, kube-system                               | 80         |
| `loki.yaml`             | `loki`             | same-namespace, monitoring                                | 3100       |
| `minio.yaml`            | `minio`            | same-namespace, kube-system, database, velero, monitoring | 9000, 9001 |
| `database.yaml`         | `database`         | same-namespace, cnpg-system, monitoring                   | any        |
| `redis.yaml`            | `redis`            | same-namespace, keda, monitoring                          | 6379       |
| `cnpg-system.yaml`      | `cnpg-system`      | same-namespace, monitoring                                | any        |
| `kube-system.yaml`      | `kube-system`      | same-namespace, all-namespaces (DNS), monitoring          | 53/UDP+TCP |
| `velero.yaml`           | `velero`           | same-namespace, monitoring                                | any        |
| `keda.yaml`             | `keda`             | same-namespace, monitoring                                | any        |

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
    - fromEntities: # allows node/host traffic (API server webhooks, kubelet probes, NodePort ingress)
        - remote-node
        - world
```

Key behavior:

- **Implicit deny-all**: `endpointSelector: {}` with explicit ingress `from*` rules drops all inbound traffic that does not match. There is no separate "deny-all" resource.
- **Same-namespace allow**: every policy includes a `fromEndpoints` rule for its own namespace.
- **Monitoring allow**: every namespace with scrape targets allows inbound from `monitoring` on any port — Prometheus ServiceMonitors/PodMonitors discover endpoints dynamically.
- **Namespace-explicit allow**: service-to-service dependencies use `fromEndpoints` + `toPorts`.
- **Host/node traffic**: every policy allows `remote-node` (traffic from other cluster nodes, including kube-apiserver) and `world` (external traffic via NodePort). Without this, kubelet health probes, API server webhooks, and external ingress would be blocked.

## Traffic Flow Example

```
Internet → NodePort (via Cilium eBPF)
  → Cilium Gateway API (kube-system, cilium-agent)
    → argocd-server.argocd.svc:80       ← allowed by argocd.yaml
    → grafana.monitoring.svc:80         ← allowed by monitoring.yaml
    → vault.vault.svc:8200              ← allowed by vault.yaml
    → minio.minio.svc:9000              ← allowed by minio.yaml

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
