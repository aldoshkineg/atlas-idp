# Cilium — Networking, Load Balancing & Gateway

Cilium is the single eBPF dataplane of the cluster: CNI, kube-proxy replacement,
LoadBalancer (L2/ARP), Gateway API ingress and network policy engine. No MetalLB, no
cloud LB, no ingress-nginx.

## Installation

Cilium (chart **1.19.4**) is installed by Terraform (`infra/modules/cilium/`,
`helm_release` into `kube-system`) during cluster provisioning — it must exist before
Argo CD. GitOps then layers LB pools, Gateway resources and routes on top.

Key values (module defaults + `infra/environments/stage/main.tf`):

| Setting                                     | Value / why                                            |
| ------------------------------------------- | ------------------------------------------------------ |
| `kubeProxyReplacement: true`                | full eBPF service handling, no kube-proxy              |
| `k8sServiceHost/Port: localhost:7445`       | Talos KubePrism endpoint                               |
| `gatewayAPI.enabled: true` (+ `enableAlpn`) | Cilium is the GatewayClass controller                  |
| `l2announcements.enabled: true`             | ARP announcements for LoadBalancer VIPs                |
| `hubble.enabled: true`                      | network flow observability (agent-level; relay/UI off) |
| `bpf.hostLegacyRouting: true`               | compatibility on the Incus/Talos topology              |

## Load balancing (no cloud, no MetalLB)

`gitops/platform/base/resources/loadbalancer/`:

- `CiliumLoadBalancerIPPool default-pool` — VIPs from **10.200.10.100–10.200.10.200**.
- `CiliumL2AnnouncementPolicy default-pool-policy` — announces LB and external IPs via
  ARP on `eth0`.

This is distinct from the Talos **control-plane** VIP `10.200.10.10` — see
[`cluster-internals.md`](cluster-internals.md) for the two-VIP explanation.

> **Incus gotcha:** L2 announcements answer ARP for IPs Incus never assigned, so the
> bridge must run with `security.ipv4_filtering=false` and `security.mac_filtering=false`
> — details in [`talos.md`](talos.md).

## Gateway API

- CRDs `v1.2.1` (`gitops/platform/base/gateway-api-crds.yaml`), GatewayClass `cilium`.
- One shared `Gateway platform-gateway` in `kube-system` with per-service HTTPS
  listeners (TLS terminate, certs from `atlas-ca-issuer`): `test-ca.atlas`,
  `grafana.atlas`, `vault.atlas`, `s3.atlas`, `console.s3.atlas`, `argocd.atlas`,
  `argocd-cli.atlas` (h2c/gRPC — see
  [`runbooks/argocd-grpc-login.md`](runbooks/argocd-grpc-login.md)), `seal.atlas`.
- `HTTPRoute`s live in `gitops/platform/base/resources/gateway-routes/` (one file per
  service: route + `Certificate`). Workload routes (e.g. seal) are added by
  `atlasctl enable`.
- `restart-cilium-operator` is a PostSync hook Job that restarts the cilium-operator
  once the Gateway CRDs land, so the controller picks them up — a bootstrap-ordering fix.

Traffic path: client → LB VIP (ARP) → eBPF → Gateway Envoy → identity
`reserved:ingress` → backend pod. Network policies must allow `fromEntities: ingress`
for gateway-routed namespaces (see [`security.md`](security.md)).

## Network policy

Cilium enforces both platform-level `CiliumNetworkPolicy` (default-deny ingress per
namespace) and workload-level policies generated from the golden template. Covered in
[`security.md`](security.md).

## Real usage

```bash
make test-ca-gateway     # deploys a whoami app + cert + HTTPRoute, curls
                         # https://test-ca.atlas through the LB VIP with our CA
cilium status            # dataplane health
kubectl get gateway -n kube-system            # platform-gateway Programmed
kubectl get ippools.cilium.io                 # VIP allocation
```

## See also

- [`talos.md`](talos.md) — kube-proxy replacement notes, Incus bridge filtering
- [`cluster-internals.md`](cluster-internals.md) — verified LB/VIP internals
