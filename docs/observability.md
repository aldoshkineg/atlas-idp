# Observability — Metrics, Logs, Traces

Full triad on self-hosted components: Prometheus/Grafana/Alertmanager (metrics),
Loki (logs), Tempo (traces), with Grafana Alloy as the single collector for logs and
OTLP traces. Everything runs in the `observability` GitOps layer.

## Components

| Component             | App manifest (`gitops/platform/observability/`) | Chart / version                | Namespace       | Wave |
| --------------------- | ----------------------------------------------- | ------------------------------ | --------------- | ---- |
| kube-prometheus-stack | `prom-stack.yaml`                               | `kube-prometheus-stack` 68.2.0 | `monitoring`    | 6    |
| Loki                  | `loki.yaml`                                     | `loki` 7.0.0                   | `loki`          | 7    |
| Tempo                 | `tempo.yaml`                                    | `tempo` 1.24.4                 | `observability` | 7    |
| Alloy                 | `alloy.yaml`                                    | `alloy` 1.9.0                  | `monitoring`    | 8    |
| platform-monitors     | `monitor.yaml` (raw manifests)                  | —                              | `monitoring`    | 11   |
| metrics-server        | `metrics-server.yaml`                           | `metrics-server` 3.12.2        | `kube-system`   | 2    |

## Pipelines

```
metrics:  ServiceMonitor/PodMonitor ──► Prometheus ──► Grafana / Alertmanager
logs:     pod logs ──► Alloy (daemonset, loki.source.kubernetes) ──► Loki (loki-gateway)
traces:   app OTLP http :4318 ──► Alloy (otelcol.receiver) ──► Tempo :4317 ──► Grafana
```

Workloads only need one contract: expose `/metrics` (picked up by a
ServiceMonitor/PodMonitor) and send OTLP to `http://alloy.monitoring:4318`.

## Our configuration

- **Prometheus:** retention **2d / 1GB**, 1Gi PVC on `linstor-replicated`;
  `*SelectorNilUsesHelmValues: false` — scrapes every ServiceMonitor/PodMonitor in the
  cluster without label gymnastics. Operator webhook certs come from cert-manager
  (`atlas-ca-issuer`).
- **Grafana:** exposed at `https://grafana.atlas` via the platform gateway; admin
  password is Vault-backed (`grafana-admin` ExternalSecret). Datasources provisioned:
  Prometheus, Loki (`loki-gateway.loki.svc`), Tempo (`tempo.observability.svc:3200`).
  Custom dashboard `atlas-idp-platform-overview` plus per-workload dashboards.
- **Loki:** SingleBinary mode, 1Gi PVC, TSDB schema v13, **retention 10d** with
  compactor-based deletion, no multi-tenancy (`auth_enabled: false`).
- **Tempo:** single instance, 1Gi PVC, OTLP gRPC 4317, query 3200.
- **Alloy:** daemonset; two pipelines only — Kubernetes pod logs → Loki, OTLP 4318 →
  Tempo. No Promtail, no separate OTEL collector.
- **Alerts** (`values/alert-rules.yaml`): `HighErrorRate` (5xx ratio > 5% over 5m) and
  `HPAMaxedOut` (HPA pinned at max for 15m).
- **Platform monitors** (`resources/monitor/`): Redis ServiceMonitor and CNPG
  `production-db` PodMonitor; node-exporter and kube-state-metrics come with the stack.

## Reference workload wiring (seal)

- ServiceMonitors for api/worker rendered by the Helm chart (15s interval).
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring:4318` injected via values —
  traces are queryable in Grafana with TraceQL (`seal-.*` services); dashboards in
  `gitops/workloads/atlasteam/seal/resources/monitoring/`.

## Real usage

```bash
kubectl -n monitoring get servicemonitors,podmonitors -A   # what Prometheus scrapes
# Grafana: https://grafana.atlas (admin / Vault secret/platform/grafana)
# Explore → Loki:  {namespace="atlasteam-seal"}
# Explore → Tempo: {resource.service.name=~"seal-.*"}
```

Network note: the `monitoring` namespace is allowed by every platform
CiliumNetworkPolicy specifically so Prometheus can scrape and Alloy can push — see
[`security.md`](security.md).

## Known limitations

- Short retention (2d metrics / 10d logs) and 1Gi volumes — lab sizing, tuned via values.
- Hubble relay/UI are off; network flows are available on the agents but not scraped.
- No dedicated ServiceMonitors for Cilium/Argo CD yet.

## See also

- [`scaling.md`](scaling.md) — metrics-server & HPA/KEDA signals
- [`tech-stack.md`](tech-stack.md) — why this stack
