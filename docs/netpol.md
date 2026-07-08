# Network Policies in Atlas IDP

## Overview

Atlas IDP uses Kubernetes NetworkPolicy to enforce **namespace-level isolation** with a **default-deny ingress** model. Platform namespaces are protected by baseline policies deployed as an ArgoCD Application. Workload namespaces get a generated policy from a template at scaffold time.

---

## Architecture

### Two Layers of NetworkPolicy

```
┌─────────────────────────────────────────────────────┐
│                   Platform Layer                     │
│  gitops/platform/security/netpol.yaml  │
│    └── network-policies/ (13 per-namespace files)    │
│        argocd, vault, minio, database, redis, ...    │
│                                                      │
│  Sync-wave: 10                                       │
│  Covers all platform namespaces                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                  Workload Layer                       │
│  workloads/<group>/<app>/infra/network-policy.yaml   │
│                                                      │
│  Generated from: templates/gold/infra/               │
│                    network-policy.yaml.tmpl           │
│                                                      │
│  Synced to gitops/workloads/<group>/<app>/resources/ │
│  on atlasctl enable                                  │
└─────────────────────────────────────────────────────┘
```

### How It Works

Each NetworkPolicy uses:

```yaml
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

- `podSelector: {}` — applies to **all pods** in the namespace
- `policyTypes: [Ingress, Egress]` — enables isolation for both directions
- An empty `ingress:` or `egress:` list (i.e. only the default-deny) would block everything
- **Implicit deny-all**: any traffic that does not match an explicit allow rule is dropped

---

## Platform Layer Policies

13 namespaces protected, each in its own file:

| File | Namespace | Allows inbound from | Port(s) |
|------|-----------|-------------------|---------|
| `argocd.yaml` | `argocd` | same-ns, nginx-gateway-fabric, monitoring | 80 |
| `vault.yaml` | `vault` | same-ns, nginx-gateway-fabric, external-secrets, monitoring | 8200 |
| `external-secrets.yaml` | `external-secrets` | same-ns, monitoring | any |
| `nginx-gateway.yaml` | `nginx-gateway-fabric` | same-ns, monitoring | any |
| `monitoring.yaml` | `monitoring` | same-ns, nginx-gateway-fabric | 80 |
| `loki.yaml` | `loki` | same-ns, monitoring | 3100 |
| `minio.yaml` | `minio` | same-ns, nginx-gateway-fabric, database, velero, monitoring | 9000, 9001 |
| `database.yaml` | `database` | same-ns, cnpg-system, monitoring | any |
| `redis.yaml` | `redis` | same-ns, keda, monitoring | 6379 |
| `cnpg-system.yaml` | `cnpg-system` | same-ns, monitoring | any |
| `kube-system.yaml` | `kube-system` | same-ns, all-ns (DNS port 53), monitoring | 53/UDP+TCP |
| `velero.yaml` | `velero` | same-ns, monitoring | any |
| `keda.yaml` | `keda` | same-ns, monitoring | any |

All policies include a **same-namespace allow** (`podSelector: {}` in `from`) so internal pod-to-pod communication works within each namespace.

### Deployed via ArgoCD

```yaml
# gitops/platform/security/netpol.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"
```

Sync-wave 10 ensures all platform namespaces already exist before policies are applied.

---

## Workload Layer Policies

When a new workload is scaffolded with `atlasctl new`, a NetworkPolicy is generated from the template:

```
templates/gold/infra/network-policy.yaml.tmpl
```

### Template

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{APP}}
  namespace: {{NAMESPACE}}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: nginx-gateway-fabric
      ports:
        - port: {{GATEWAY_PORT}}
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
      ports:
        - port: 443
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: database
      ports:
        - port: 5432
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: minio
      ports:
        - port: 9000
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: redis
      ports:
        - port: 6379
```

### Variables

| Variable | Source | Default |
|----------|--------|---------|
| `{{APP}}` | CLI argument | required |
| `{{NAMESPACE}}` | `--namespace` or `<group>-<app>` | `<group>-<app>` |
| `{{GATEWAY_PORT}}` | hardcoded in `render_template` | `8080` |

### Lifecycle

1. **`atlasctl new`** — renders template → `workloads/<group>/<app>/infra/network-policy.yaml`
2. **`atlasctl enable`** — copies policy to `gitops/workloads/<group>/<app>/resources/infra/`
3. **ArgoCD** — applies it in the workload namespace (synced as part of the workload Application)

---

## Traffic Flows

### Platform Ingress

```
Internet → NodePort 30444
  → nginx-gateway-fabric (egress unrestricted)
    → argocd-server.argocd.svc:80        ← allowed by argocd.yaml
    → grafana.monitoring.svc:80          ← allowed by monitoring.yaml
    → vault.vault.svc:8200               ← allowed by vault.yaml
    → minio.minio.svc:9000               ← allowed by minio.yaml
```

### Application Ingress

```
Internet → NodePort 30444
  → nginx-gateway-fabric (egress unrestricted)
    → seal-api.atlasteam-seal.svc:8080   ← allowed by workload policy
```

### Monitoring Scraping

```
Prometheus (monitoring NS) → *.svc:*
  ← allowed by both platform and workload policies
  (monitoring namespace is trusted — any port)
```

### Cross-Namespace Service Dependencies

```
seal-api (atlasteam-seal)
  → production-db-rw.database:5432       ← egress allowed by workload policy
  → redis-master.redis:6379              ← egress allowed by workload policy
  → minio.minio:9000                     ← egress allowed by workload policy
```

### DNS and API Server

```
Every pod
  → kube-dns.kube-system:53/UDP+TCP      ← egress allowed by all policies
  → kubernetes.default:443                ← egress allowed by all policies
```

### Log Shipping

```
Alloy DaemonSet (monitoring)
  → loki-gateway.loki:3100                ← ingress allowed by loki.yaml
```

---

## Namespaces Without NetworkPolicy

| Namespace | Reason |
|-----------|--------|
| `cert-manager` | No inbound traffic expected (webhooks go through API server, bypassing NetworkPolicy). PodMonitor disabled. |
| `storage` | CSI hostpath components communicate via Unix sockets or host-network kubelet. |
| `default` | No platform workloads. |
| `cronjob` | No active pods (RBAC only). |

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Default-deny ingress, permissive egress** (platform) | Egress rules are harder to debug and often cause regressions. Both directions are defined in the template, but platform policies only lock ingress. |
| **Ingress + Egress** (workload template) | Workloads follow a stricter model — only known outbound destinations are allowed. |
| **Prometheus gets any port** | ServiceMonitors/PodMonitors discover ports dynamically. Restricting by port would require updating policies whenever monitoring targets change. |
| **Same-namespace allow always included** | Prevents internal communication from breaking (e.g., seal-ui → seal-api, Prometheus → Grafana within monitoring). |
| **`kubernetes.io/metadata.name` label selector** | This label is automatically added by Kubernetes 1.21+ for every namespace. Reliable and simple. |
| **No `--gateway-port` CLI flag** | Port is hardcoded to 8080 in the template. Change it manually in the generated file if needed. |
| **Sync-wave 10 for platform policies** | Ensures all platform namespaces already exist before NetworkPolicy resources are created. |

---

## Verification

```bash
# List all NetworkPolicies in the cluster
kubectl get networkpolicies --all-namespaces

# Check a specific namespace
kubectl describe networkpolicies -n <namespace>

# Verify connectivity (requires a debug pod)
kubectl run tmp -it --image=nicolaka/netshoot --rm -- /bin/sh
  curl -v http://production-db-rw.database:5432
```
