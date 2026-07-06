# GitOps — Argo CD App-of-Apps

Root application (`gitops/bootstrap/root-app.yaml`) manages two independent trees via multi-source.

## Structure

```
gitops/
├── bootstrap/
│   └── root-app.yaml               ← multi-source, manages platform + workloads
├── platform/layers/                ← project: platform (sync-wave -1 .. 10)
│   ├── bootstrap/platform.yaml
│   ├── base/          metrics-server, keda, argo-rollouts
│   ├── networking/    gateway-api-crds, cilium-gateway, gateways
│   ├── data/          cnpg-operator, redis, postgres-cluster
│   ├── observability/ kube-prometheus-stack, loki, alloy, tempo
│   ├── security/      cert-manager, vault-operator, vault-secrets-webhook
│   └── storage/       snapshot-crds/controller, minio, linstor, velero
└── workloads/layers/               ← project: workloads (sync-wave 100+)
    ├── bootstrap/workloads.yaml
    ├── backend-api/
    ├── worker/
    └── cronjob/
```

## Sync Waves

| Wave | Layer              | Content                                                                 |
| ---- | ------------------ | ----------------------------------------------------------------------- |
| -1   | bootstrap          | AppProjects                                                             |
| 0    | Storage operators  | linstor-operator, snapshot-crds, cert-manager                           |
| 1    | Storage cluster    | linstor-cluster, cert-manager-issuers, vault-operator, gateway-api-crds |
| 2    | Base + controllers | vault-secrets-webhook, metrics-server, cnpg-operator                    |
| 3    | Storage consumers  | external-secrets, snapshot-controller                                   |
| 4    | Platform secrets   | platform-secrets                                                        |
| 5    | Data services      | minio, gateway-resources, velero                                        |
| 6    | Data tier          | redis                                                                   |
| 7    | Observability      | kube-prometheus-stack, loki, tempo, gateway-routes                      |
| 8    | Agents + extras    | alloy, keda, argo-rollouts-crds, trivy-operator                         |
| 9    | Data clusters      | argo-rollouts, postgres-cluster                                         |
| 10   | Network policies   | network-policies                                                        |

## RBAC Isolation

| Project     | Destinations        | Cluster Resources                              |
| ----------- | ------------------- | ---------------------------------------------- |
| `platform`  | Platform namespaces | CRDs, ClusterIssuer, GatewayClass, ClusterRole |
| `workloads` | atlasteam-seal      | CCNP, ClusterRole                              |

## Adding New Services

- **Platform:** create `.yaml` in `platform/layers/<layer>/` with `project: platform`
- **Workload:** create `.yaml` in `workloads/layers/<app>/` with `project: workloads`

## Verification

```bash
argocd app list
argocd app get root-app
```
