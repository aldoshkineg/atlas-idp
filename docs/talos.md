# Talos Cluster Notes

> Operational notes and gotchas for the Talos + Incus platform.
> Infrastructure provisioning lives in `infra/modules/`; storage in `docs/linstor.md`;
> Incus VM/host management in `docs/incus-management.md`.

## Terminology: DRBD, not RBD

LINSTOR's underlying replication technology is **DRBD** (Distributed Replicated Block Device).
Do not confuse it with **RBD** (RADOS Block Device), which is the Ceph ecosystem protocol.
When talking about the Talos/LINSTOR stack, always use DRBD.

## Talos kernel modules for DRBD

Worker (and control-plane) nodes load the DRBD kernel modules at boot via the Talos
machine config (`machine.kernel.modules`):

```yaml
machine:
  kernel:
    modules:
      - name: drbd
      - name: drbd_transport_tcp
```

The `siderolabs/drbd` system extension (v9.x) must be present in the Talos image
(see `docs/linstor.md` for the LINSTOR satellite specifics on Talos).

## Networking: Cilium as kube-proxy replacement + LoadBalancer

Cilium runs in native eBPF mode and replaces `kube-proxy` entirely. LoadBalancer
services are provided by Cilium without MetalLB, using **L2 Announcements** (gratuitous
ARP) or BGP.

```yaml
# cilium values (summary)
kubeProxyReplacement: true
l2announcements:
  enabled: true
externalIPs:
  enabled: true
```

Load balancer IPs are allocated from a `CiliumLoadBalancerIPPool` (e.g. `10.200.10.200-250`)
that must not overlap with the Incus DHCP range.

### Incus bridge filtering gotcha (CRITICAL)

When Cilium announces LoadBalancer IPs via L2 (ARP), the Incus-managed bridge must allow
VMs to answer ARP for IP addresses that were **not** assigned to them by Incus DHCP.
By default a managed Incus bridge blocks such traffic when filtering is enabled.

Ensure the Incus network profile disables IP/MAC filtering:

```yaml
config:
  "ipv4.address"            = "10.200.10.1/24"
  "ipv4.dhcp"               = "true"
  "ipv4.nat"                = "true"
  "security.ipv4_filtering" = "false"   # CRITICAL: lets Cilium announce LB IPs
  "security.mac_filtering"  = "false"   # CRITICAL: same reason
```

If LoadBalancer IPs are unreachable from the host while pods/logs look healthy,
re-check these two flags first.

## Acceptance criteria (cluster healthy)

- `talosctl health` reports all nodes `Ready`, etcd healthy, kubelet healthy.
- LINSTOR satellite pods initialize the LVM pools on the secondary VM disks; a test PVC
  reaches `Bound`.
- A `type: LoadBalancer` service for a test app gets an IP from the Cilium pool and is
  reachable from the host via `curl`.
- Cilium `kube-proxy` replacement active (no `kube-proxy` pods running).
