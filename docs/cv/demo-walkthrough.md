# Demo Walkthrough — A Day on the Platform

> A single end-to-end scenario that exercises every platform primitive at once.
> Use it as the "live demo" story in an interview: one tenant request that
> touches IaC, GitOps, networking, storage, security, observability, and DR.

---

## Scenario: a tenant team ships a new service

**1. Self-service scaffold**
`atlasctl new orders --group shop --repo git@github.com:org/orders`
→ generates a workload from a golden-path template (`templates/gold`), creating
the `workloads/shop/orders` entry and its Argo CD `AppProject`/`Application`.
Nothing is clicked in a UI; the platform product is the CLI.

**2. GitOps reconciliation**
The PR merge triggers Argo CD (app-of-apps, `gitops/bootstrap/root-app.yaml`).
The platform layers apply in dependency order
(`base` → `security` → `storage` → `delivery`) via
`argocd.argoproj.io/depends-on`, so foundation (cert-manager, gateway-api,
Vault, Linstor, external-secrets) exists before the workload.

**3. Ingress via Gateway API**
The service exposes itself through an `HTTPRoute`
(`apps/seal/charts/seal/templates/httproute.yaml`) on the Cilium Gateway, which
already holds a LoadBalancer VIP (`10.200.10.100` from the Cilium LB IPAM pool).

**4. Progressive delivery**
`seal-api` ships as an Argo Rollouts `Rollout` (`rollout-api.yaml`) — a canary,
not a big-bang deploy. Bad metrics auto-rollback.

**5. Event-driven scaling**
`seal-worker` scales via KEDA (`keda-scaledobject.yaml`) on the length of a
Redis list — autoscaling on a real signal, not just CPU.

**6. Secrets, the right way**
No secret is committed. An `ExternalSecret`
(`workloads/atlasteam/seal/secrets.yaml`) pulls from Vault
(`tools/vault/`) at sync time via the External Secrets Operator.

**7. Stateful, replicated storage**
Postgres (CloudNativePG), Redis, and MinIO persist on the `linstor-replicated`
StorageClass (`autoPlace=2`) — DRBD replication survives a node loss, no cloud
volume required.

**8. Security gates**
The image must be Cosign-signed; Kyverno's `require-image-signature` policy
rejects unsigned images at admission, while `disallow-privileged` /
`run-as-non-root` enforce Pod Security. Cilium `CiliumNetworkPolicy` restricts
east-west traffic.

**9. Observability, out of the box**
The app emits metrics (Prometheus), structured logs (Loki), and OTLP traces
(Tempo via Alloy). Dashboards and alert rules are pre-wired; Hubble shows
network flows.

**10. Disaster recovery is tested**
Velero snapshots to MinIO on Linstor; CNPG streams backups. Restore is not
theoretical — it is exercised in `tests/velero/` and `tests/db-backup/`.

---

## 30-second verbal version (interview)

> "A tenant runs `atlasctl new`, gets a golden-path scaffold, opens a PR, and
> Argo CD delivers it through layered, dependency-ordered GitOps. The service
> gets a Gateway-API ingress on a Cilium LoadBalancer VIP, a canary rollout,
> KEDA autoscaling on Redis, Vault secrets via ESO, and replicated Linstor
> storage. Kyverno gates unsigned images, Hubble/Prometheus/Loki/Tempo observe
> it, and Velero DR is actually tested. All of it runs on bare-metal Talos +
> Incus — no cloud lock-in."

---

## File map for the demo

| Step          | Where to point                                                                   |
| ------------- | -------------------------------------------------------------------------------- |
| scaffold      | `tools/atlasctl/cmd/new.go`, `templates/gold/`                                   |
| gitops        | `gitops/bootstrap/root-app.yaml`, `gitops/platform/layers/*.yaml`                |
| ingress       | `apps/seal/charts/seal/templates/httproute.yaml`, `docs/cv/cluster-internals.md` |
| delivery      | `apps/seal/charts/seal/templates/rollout-api.yaml`                               |
| scaling       | `apps/seal/charts/seal/templates/keda-scaledobject.yaml`                         |
| secrets       | `workloads/atlasteam/seal/secrets.yaml`, `tools/vault/`                          |
| storage       | `gitops/platform/base/linstor-*.yaml`, StorageClass `linstor-replicated`         |
| security      | `gitops/platform/security/kyverno-policies/`, `security/cosign`, `ccnp-*.yaml`   |
| observability | `gitops/platform/observability/` (prom-stack, loki, tempo, alloy)                |
| DR            | `gitops/platform/storage/minio.yaml`, `tests/velero/`, `tests/db-backup/`        |
