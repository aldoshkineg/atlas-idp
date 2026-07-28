# Cluster Internals — Load Balancing (LB/VIP) & CSI Storage

> Verified live against the running Talos cluster. Commands shown are real and
> reproducible (`kubectl ...`). This is the "how it actually works" companion to
> `tech-stack.md` for the networking and storage rows.

> **Two distinct VIPs — do not confuse them:**
>
> - **Control-plane VIP** (§0): stable endpoint for the Kubernetes API server /
>   `talosctl` — `10.200.10.10`. Managed by Talos itself.
> - **Service VIPs** (§1): Cilium LoadBalancer addresses for in-cluster
>   Services — `10.200.10.100–200`. Managed by Cilium LB IPAM.

---

## 0. Control Plane VIP (Talos) — the cluster API endpoint

A floating VIP that keeps the Kubernetes API server reachable across control-plane
failures. It is **Talos-native** — no kube-vip, keepalived, or cloud LB.

### Mechanism

- Defined in `infra/modules/talos-config/main.tf`.
- `cp_endpoint = "https://${local.use_vip ? var.cluster_vip : local.cp_ips[0]}:${var.api_server_port}"`
  — when HA is enabled, both the kube-apiserver URL and the `talosctl` `endpoints`
  use the floating VIP instead of a single node IP.
- The VIP is attached to the control-plane node's interface through the Talos
  machine config field `machine.network.interfaces[].vip.ip` (applied to the first
  CP node in the patch loop). Talos manages the floating IP (leader election among
  control planes + gratuitous ARP/NDP on the LAN), so the API endpoint survives a
  CP node loss.
- `use_vip = length(local.cp_ips) > 1 && var.cluster_vip != ""` — the VIP
  engages automatically for multi-control-plane clusters.

### Values

```hcl
# infra/environments/stage/variables.tf
variable "cluster_vip" { default = "10.200.10.10" }   # floating CP VIP
variable "controlplane_count" { default = 1 }          # HA when >= 2

# infra/modules/talos-config/main.tf
cp_ips default = ["10.200.10.11", "10.200.10.12", "10.200.10.13"]  # for 3 CPs
```

The VIP is wired into `cp_endpoint`, the `talosctl` `endpoints`, and the CP
interface `vip` field. Scaling to an HA control plane is a single variable
change (`controlplane_count >= 2`) — no code changes.

### Why this is senior-value

Shows HA control-plane designed in from day one (floating VIP, stable API
endpoint). Scaling to HA is a one-line IaC change, not a re-architecture —
exactly the trade-off a senior platform engineer documents.

---

## 1. Load Balancing & VIP (Cilium, no cloud / no MetalLB)

The cluster has **no cloud load balancer and no MetalLB**. Cilium's eBPF
dataplane provides Service LoadBalancer IPs and advertises them on the local
LAN itself.

### Mechanism

- **kube-proxy replacement**: `kube-proxy-replacement: true` — Cilium handles
  all Service NAT/load balancing in eBPF, kube-proxy is not used.
- **LB IPAM**: `enable-lb-ipam: true`, `default-lb-service-ipam: lbipam` —
  LoadBalancer IPs are allocated from a Cilium-managed pool, not by a cloud.
- **L2 announcements**: `enable-l2-announcements: true` — the node hosting the
  backing pod announces the VIP via **ARP** on the LAN, so external clients
  (e.g. on `10.200.10.0/24`) can route to it. This is the bare-metal equivalent
  of a cloud LB VIP.
- **Pod networking**: `routing-mode: tunnel` / `tunnel-protocol: vxlan`,
  cluster-pool IPAM `10.0.0.0/8` (/24 per node).

### Evidence

```bash
# VIP pool (100 addresses)
kubectl get CiliumLoadBalancerIPPool default-pool -o jsonpath='{.spec}'
# {"blocks":[{"start":"10.200.10.100","stop":"10.200.10.200"}],"disabled":false}

# Gateway already holding a VIP from the pool
kubectl -n kube-system get svc cilium-gateway-platform-gateway
# NAME                          TYPE           EXTERNAL-IP     PORT(S)
# cilium-gateway-platform-gateway  LoadBalancer  10.200.10.100   443:30918/TCP

# Per-node Pod CIDRs (cluster-pool)
kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.ipam.podCIDRs}{"\n"}{end}'
# talos-6rx-cua ["10.0.2.0/24"]
# talos-b6c-rv0 ["10.0.1.0/24"]
# talos-boo-xox ["10.0.0.0/24"]
```

### Why this is senior-value

Demonstrates a **self-hosted, bare-metal LoadBalancer** with VIP/ARP
announcements — the exact problem cloud users never solve. No dependency on
ELB/LoadBalancer controllers or MetalLB config drift.

---

## 2. CSI / Replicated Storage (Linstor / Piraeus + DRBD)

Block storage is provided by **LINSTOR** (LINBIT), deployed via the Piraeus
operator, backed by **DRBD** for synchronous replication. This replaces cloud
block storage (EBS/PD) on bare metal.

### Topology

- Namespace: `piraeus-datastore`
- Operator: Piraeus `linstor-cluster` chart 1.1.1 (LINSTOR 1.33.2)
- Components: `linstor-controller`, `linstor-csi-controller`, `linstor-csi-node`
  (per node), `linstor-satellite` (per node — the DRBD/data plane),
  `linstor-affinity-controller`.
- Storage nodes (satellites): the two worker nodes
  (`talos-6rx-cua`, `talos-b6c-rv0`); control-plane node is not a storage node.

### StorageClass

```bash
kubectl get storageclass linstor-replicated -o jsonpath='{.parameters}'
# {"autoPlace":"2","storagePool":"lvm-pool"}
```

- `autoPlace: 2` → every volume is replicated to **2 nodes** (DRBD), surviving a
  single node loss.
- `storagePool: lvm-pool` → LVM **thin** pool `linstor-vg/linstor-thin`.
- `volumeBindingMode: WaitForFirstConsumer`, `allowVolumeExpansion: true`.

### Storage pools (live)

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor sp list
# lvm-pool | talos-6rx-cua | LVM_THIN | linstor-vg/linstor-thin | 6.57 GiB | Ok | CanSnapshots=True
# lvm-pool | talos-b6c-rv0 | LVM_THIN | linstor-vg/linstor-thin | 6.61 GiB | Ok | CanSnapshots=True
```

Thin provisioning + `CanSnapshots=True` enables CSI snapshots (used by
CloudNativePG and Velero backup paths).

### Real workloads on replicated storage

```bash
kubectl get pvc -A | grep linstor-replicated
# vault/file, redis-data, minio, prometheus/grafana/alertmanager, loki, tempo,
# cnpg production-db  → all Bound on linstor-replicated (autoPlace=2)
```

### Why this is senior-value

True **HA block storage on bare metal** with replication, thin provisioning, and
snapshot capability — the hardest part of leaving a cloud, solved with DRBD
rather than a managed volume service. Backs the platform's stateful tier
(Vault, Postgres, Redis, MinIO, monitoring) with node-loss tolerance.

---

## Summary

- **Control-plane VIP**: Talos-native floating VIP `10.200.10.10` (no kube-vip),
  wired into `cp_endpoint` + `talosctl` endpoints; auto-disabled for single-CP,
  one-line toggle to HA.
- **LB/VIP**: Cilium eBPF (`kube-proxy-replacement`) + LB IPAM +
  L2/ARP announcements → cloud-free LoadBalancer VIPs from
  `10.200.10.100–10.200.10.200`.
- **CSI**: LINSTOR/DRBD via Piraeus → replicated (`autoPlace=2`), thin,
  snapshot-capable LVM storage on bare metal, no cloud volumes.
