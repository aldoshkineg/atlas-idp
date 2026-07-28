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

  - **Incus**: lightweight VM/container platform with a modern REST API,
  native clustering and unified management of VMs and system containers.
  Chosen over libvirt, Proxmox and similar platforms because it provides
  excellent automation support, significantly lower operational overhead,
  and production-grade virtualization without requiring a heavyweight
  virtualization stack.
- **Talos**: immutable, API-only OS (no SSH, no shell). Machine config as code;
  DRBD kernel modules via `machine.kernel.modules` + the `siderolabs/drbd`
  extension baked into the image.
- **Control-plane HA**: Talos-native floating VIP `10.200.10.10`
  (`machine.network.interfaces[].vip.ip`) — no kube-vip/keepalived; auto-disabled
  for single-CP topologies (`use_vip` in `talos-config`).

## Alternatives considered

- **kind / k3d** — rejected: containerized nodes can't exercise DRBD block
  replication, L2/ARP load balancing or OS upgrade flows; removed from the repo
  (`refactor(kind): remove Kind dev environment...`).
- **Managed cloud (EKS/GKE)** — rejected: control plane, LB and volumes become
  vendor black boxes; recurring cost; contradicts the goal of demonstrating
  no-cloud operations.
- **kubeadm on generic VMs** — rejected: mutable OS, imperative lifecycle,
  no declarative machine config.
- **libvirt** — rejected: provides a low-level virtualization API but leaves
  clustering, automation and operational workflows to external tooling. Incus
  offers a higher-level management model with a modern REST API, native
  clustering and simpler Terraform integration.
- **Proxmox VE / XCP-ng** — rejected: full virtualization platforms with rich
  management capabilities, but they introduce additional infrastructure
  services and operational overhead that are unnecessary for this project.
  Incus provides the required virtualization features while remaining lighter,
  easier to automate and better suited for infrastructure-as-code workflows.

## Consequences

- Real ops surface: disk/bootstrap/upgrade problems are ours (see `docs/talos.md`,
  `docs/incus.md`, `docs/linstor.md` gotchas).
- Incus bridge must run with `security.ipv4_filtering=false` /
  `security.mac_filtering=false` or Cilium L2 announcements break (ADR-002).
- Everything is reproducible from `make act-ci` on any Linux host with enough RAM
  (`docs/requirements.md`); no cloud account is ever required.
- Talos has no shell — all debugging goes through `talosctl`, which raises the
  operational bar but enforces the immutable model.
