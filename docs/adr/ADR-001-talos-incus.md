# ADR-001: Talos Linux on Incus VMs as the cluster foundation

**Status:** Accepted
**Date:** 2026-07

## Context

The platform needs a Kubernetes runtime that is reproducible, close to production
bare-metal operations, and free of cloud-account dependencies. The original
iteration ran on **kind** with EKS/AWS stubs; that hid every hard problem a
platform engineer actually owns: OS lifecycle, control-plane HA, storage, load
balancing, node networking.

## Decision

Run Kubernetes on **Talos Linux** VMs provisioned by **Incus** on a Linux host,
fully driven by Terraform/OpenTofu (`infra/modules/{incus,talos-config,talos-cluster}`).

- **Talos**: immutable, API-only OS (no SSH, no shell). Machine config as code;
  DRBD kernel modules via `machine.kernel.modules` + the `siderolabs/drbd`
  extension baked into the image.
- **Control-plane HA**: Talos-native floating VIP `10.200.10.10`
  (`machine.network.interfaces[].vip.ip`) — no kube-vip/keepalived; auto-disabled
  for single-CP topologies (`use_vip` in `talos-config`).
- **Incus**: VM hypervisor with a managed bridge (`incusbr0`), giving bare-metal-class
  behavior (real disks, real L2 network for ARP) without cloud costs. A **Zot**
  pull-through registry cache (Terraform-managed Incus container) keeps image
  pulls local and air-gap-friendly.

## Alternatives considered

- **kind / k3d** — rejected: containerized nodes can't exercise DRBD block
  replication, L2/ARP load balancing or OS upgrade flows; removed from the repo
  (`refactor(kind): remove Kind dev environment...`).
- **Managed cloud (EKS/GKE)** — rejected: control plane, LB and volumes become
  vendor black boxes; recurring cost; contradicts the goal of demonstrating
  no-cloud operations.
- **kubeadm on generic VMs** — rejected: mutable OS, imperative lifecycle,
  no declarative machine config.

## Consequences

- Real ops surface: disk/bootstrap/upgrade problems are ours (see `docs/talos.md`,
  `docs/incus.md`, `docs/linstor.md` gotchas).
- Incus bridge must run with `security.ipv4_filtering=false` /
  `security.mac_filtering=false` or Cilium L2 announcements break (ADR-002).
- Everything is reproducible from `make act-ci` on any Linux host with enough RAM
  (`docs/requirements.md`); no cloud account is ever required.
- Talos has no shell — all debugging goes through `talosctl`, which raises the
  operational bar but enforces the immutable model.
