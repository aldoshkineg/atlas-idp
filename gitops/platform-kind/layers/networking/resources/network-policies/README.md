# Networking Layer

This layer manages cluster networking: ingress gateways, HTTP routing, and network policies.

## Files

### Ingress & Routing

| File                        | Sync-wave | Purpose                                                                   |
| --------------------------- | --------- | ------------------------------------------------------------------------- |
| `gateway-api-crds.yaml`     | 1         | Installs Gateway API CRDs (GatewayClass, Gateway, HTTPRoute)              |
| `nginx-gateway-fabric.yaml` | 3         | NGINX Gateway Fabric controller — the cluster ingress gateway             |
| `gateway-resources.yaml`    | 5         | Gateway resource with TLS listeners for `*.atlas` domain                  |
| `gateway-routes.yaml`       | 7         | HTTPRoute rules mapping hosts to services (argocd, grafana, vault, minio) |

### Network Policies

| File          | Sync-wave | Purpose                                                  |
| ------------- | --------- | -------------------------------------------------------- |
| `netpol.yaml` | 10        | ArgoCD Application deploying all NetworkPolicy resources |

### Network Policy Definitions (`network-policies/`)

| File                    | Namespace              | Allows inbound from                                                | Ports      |
| ----------------------- | ---------------------- | ------------------------------------------------------------------ | ---------- |
| `argocd.yaml`           | `argocd`               | same-namespace, nginx-gateway-fabric, monitoring                   | 80         |
| `vault.yaml`            | `vault`                | same-namespace, nginx-gateway-fabric, external-secrets, monitoring | 8200       |
| `external-secrets.yaml` | `external-secrets`     | same-namespace, monitoring                                         | any        |
| `nginx-gateway.yaml`    | `nginx-gateway-fabric` | same-namespace, monitoring                                         | any        |
| `monitoring.yaml`       | `monitoring`           | same-namespace, nginx-gateway-fabric                               | 80         |
| `loki.yaml`             | `loki`                 | same-namespace, monitoring                                         | 3100       |
| `minio.yaml`            | `minio`                | same-namespace, nginx-gateway-fabric, database, velero, monitoring | 9000, 9001 |
| `database.yaml`         | `database`             | same-namespace, cnpg-system, monitoring                            | any        |
| `redis.yaml`            | `redis`                | same-namespace, keda, monitoring                                   | 6379       |
| `cnpg-system.yaml`      | `cnpg-system`          | same-namespace, monitoring                                         | any        |
| `kube-system.yaml`      | `kube-system`          | same-namespace, all-namespaces (DNS), monitoring                   | 53/UDP+TCP |
| `velero.yaml`           | `velero`               | same-namespace, monitoring                                         | any        |
| `keda.yaml`             | `keda`                 | same-namespace, monitoring                                         | any        |

## How Network Policies Work

Each policy file implements **default-deny ingress** with explicit allow rules:

```yaml
spec:
  podSelector: {} # applies to ALL pods in the namespace
  policyTypes:
    - Ingress # enables ingress isolation
  ingress:
    - from:
        - podSelector: {} # allows same-namespace traffic
    - from: # allows cross-namespace traffic
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: <source-ns>
      ports:
        - port: <N>
```

Key behavior:

- **Implicit deny-all**: setting `policyTypes: [Ingress]` with `podSelector: {}` drops all inbound traffic that does not match any `ingress` rule. There is no separate "deny-all" resource — it is defined by the absence of matching rules.
- **Same-namespace allow**: every policy includes `podSelector: {}` in `from` so pods within the same namespace can communicate freely (e.g. Prometheus scraping Grafana inside `monitoring`).
- **Monitoring allow**: every namespace with scrape targets allows inbound from `monitoring` on any port. This is intentionally unconstrained — Prometheus ServiceMonitors/PodMonitors discover endpoints dynamically.
- **Namespace-explicit allow**: service-to-service dependencies (database → minio, keda → redis, etc.) use `namespaceSelector` + specific ports.

## Traffic Flow Example

```
Internet → NodePort 30444
  → nginx-gateway-fabric (egress unrestricted)
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
- `storage`: CSI hostpath driver components communicate via Unix sockets and host-network kubelet; no pod-to-pod inbound
- `seal`: deployed separately in `examples/`; namespace may not exist during platform bootstrap
- `default`: no platform workloads
