# ADR-002: Cilium as the single dataplane — CNI, LoadBalancer, Gateway API

**Status:** Accepted
**Date:** 2026-07

## Context

On bare metal (ADR-001) nothing provides Services of type LoadBalancer or ingress
out of the box. The conventional stack is three separate components: a CNI
(flannel/calico), MetalLB for LB VIPs, and an ingress controller
(ingress-nginx or NGINX Gateway Fabric — the latter was used in an early
iteration). Each brings its own dataplane, failure modes and upgrade cycle.

## Decision

Use **Cilium** (chart 1.19.4, Terraform-installed before Argo CD) as the single
eBPF dataplane for all four roles:

1. **CNI** with `kubeProxyReplacement: true` (Talos KubePrism endpoint
   `localhost:7445`) — no kube-proxy, no iptables service chains.
2. **LoadBalancer**: Cilium LB-IPAM (`CiliumLoadBalancerIPPool`
   `10.200.10.100–200`) + **L2 announcements** (gratuitous ARP on `eth0`) — no
   MetalLB. BGP was not needed for a single-L2 lab topology.
3. **Ingress**: **Gateway API** (CRDs v1.2.1) with GatewayClass `cilium`; one
   shared `Gateway platform-gateway` in `kube-system`, per-service HTTPS
   listeners, TLS from the internal CA. ALPN enabled — required for the gRPC/h2c
   Argo CD CLI listener (`runbooks/argocd-grpc-login.md`).
4. **Network policy**: `CiliumNetworkPolicy`/CCNP default-deny model
   (`docs/security.md`), plus Hubble flow visibility (agent-level).

## Alternatives considered

- **MetalLB + separate CNI** — rejected: second dataplane and CRD set for a
  feature Cilium ships natively (LB-IPAM + L2).
- **NGINX Gateway Fabric / ingress-nginx** — rejected after the early iteration:
  an extra hop and controller to operate; Cilium's Envoy already terminates TLS
  at the Gateway; Ingress API itself is legacy vs Gateway API.
- **kube-proxy (iptables) + plain CNI** — rejected: eBPF replacement is faster,
  and one agent handles services, policy and observability.

## Consequences

- One component to version/upgrade; but also a single point of failure — a bad
  Cilium upgrade takes networking, LB **and** ingress down together.
- L2 announcements answer ARP for IPs the hypervisor never assigned — Incus
  bridge filtering must be disabled (see ADR-001, `docs/talos.md`).
- Bootstrap ordering: Cilium is installed by Terraform (cluster has no CNI yet),
  while Gateway CRDs arrive later via GitOps — hence the `restart-cilium-operator`
  PostSync hook so the operator picks up the CRDs (`docs/cilium.md`).
- Gateway-routed traffic reaches pods with identity `reserved:ingress`; every
  network policy behind a route must allow `fromEntities: ingress`.
- Stale NGINX references may linger in older app docs (`apps/seal/doc/`) and are
  being cleaned up.
