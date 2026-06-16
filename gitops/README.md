# GitOps — Argo CD App-of-Apps

Root application (`gitops/bootstrap/root-app.yaml`) manages two independent trees via multi-source.

## Structure

```
gitops/
├── bootstrap/
│   └── root-app.yaml               ← multi-source, manages platform-kind + workloads
├── platform-kind/layers/           ← project: platform-kind (sync-wave -1 .. 7)
│   ├── bootstrap/platform-kind.yaml
│   ├── base/          metrics-server
│   ├── networking/    gateway-api-crds, nginx-gateway-fabric, gateways
│   ├── observability/ kube-prometheus-stack, loki, alloy
│   ├── security/      cert-manager, vault-operator, vault-secrets-webhook
│   └── storage/       snapshot-crds/controller, minio, csi-hostpath, velero
└── workloads/layers/               ← project: workloads (sync-wave 100+)
    ├── bootstrap/workloads.yaml
    ├── backend-api/
    ├── worker/
    └── cronjob/
```

## Sync Waves

| Wave | Layer              | Content                                                                    |
| ---- | ------------------ | -------------------------------------------------------------------------- |
| -1   | bootstrap          | AppProjects                                                                |
| 0    | CRDs + operators   | cert-manager, gateway-api-crds, vault-operator                             |
| 1    | Base services      | cert-manager-issuers, vault-secrets-webhook, metrics-server, snapshot-crds |
| 2    | Controllers        | snapshot-controller, nginx-gateway-fabric                                  |
| 3    | Storage            | minio, csi-hostpath                                                        |
| 4    | Integrations       | velero, gateway-resources                                                  |
| 5    | Observability core | kube-prometheus-stack                                                      |
| 6    | Logs + ingress     | loki, grafana-gateway, vault-gateway, minio-gateway                        |
| 7    | Log agent          | alloy                                                                      |
| 100+ | Workloads          | backend-api, worker, cronjob (reserved)                                    |

## RBAC Isolation

| Project         | Destinations                 | Cluster Resources                              |
| --------------- | ---------------------------- | ---------------------------------------------- |
| `platform-kind` | Platform namespaces          | CRDs, ClusterIssuer, GatewayClass, ClusterRole |
| `workloads`     | backend-api, worker, cronjob | None (namespaced only)                         |

## Adding New Services

- **Platform:** create `.yaml` in `platform-kind/layers/<layer>/` with `project: platform-kind`
- **Workload:** create `.yaml` in `workloads/layers/<app>/` with `project: workloads`

## Verification

```bash
argocd app list
argocd app get root-app
```
