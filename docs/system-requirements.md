# System Requirements

> Sizing guidance for the Atlas IDP platform (Talos + Incus + Cilium + LINSTOR).
> Numbers below are derived from the running `stage` cluster (3 Talos VMs on one
> Incus host) and the memory pressure observed during a full GitOps rollout.

## TL;DR

- **Host:** ≥ 24 GiB RAM (the `stage` host has 15 GiB and is swap-thrashing).
- **Control-plane VM:** ≥ 6 GiB RAM (apiserver alone eats ~2.2 GiB due to 147 CRDs).
- **Worker VM:** ≥ 8 GiB RAM each.
- **Boot disk per VM:** ≥ 20 GiB; **second disk per worker:** ≥ 20 GiB for LINSTOR.
- **vCPU:** 2 per node minimum, 4 recommended.

## Host (Incus)

| Resource | Minimum     | Recommended | Current `stage`                |
| -------- | ----------- | ----------- | ------------------------------ |
| RAM      | 16 GiB      | 24 GiB      | **15 GiB (swap 3.9 GiB used)** |
| vCPU     | 6           | 12          | 6                              |
| Disk     | 120 GiB SSD | 250 GiB SSD | —                              |

The Incus host must have enough RAM to back **all** VM allocations plus host overhead
(~1.5 GiB). If `free -m` on the host shows `Swap: used > 0`, the VMs are overcommitted
and performance will degrade — increase host RAM or shrink VM allocations.

## Control-plane node

| Resource  | Minimum | Recommended |
| --------- | ------- | ----------- |
| RAM       | 4 GiB   | 6–8 GiB     |
| vCPU      | 2       | 4           |
| Boot disk | 20 GiB  | 40 GiB      |

`kube-apiserver` memory scales with the number of API resources. This cluster carries
**147 CRDs**, which keeps the apiserver watch cache at ~2.2 GiB. On a 3.8 GiB CP VM the
node sits at ~99% and has no headroom — do not run workloads there (it is tainted
`node-role.kubernetes.io/control-plane: NoSchedule`, which is correct).

## Worker nodes (×2)

| Resource     | Minimum        | Recommended    |
| ------------ | -------------- | -------------- |
| RAM          | 4 GiB          | 8 GiB          |
| vCPU         | 2              | 4              |
| Boot disk    | 20 GiB         | 40 GiB         |
| LINSTOR disk | 20 GiB (block) | 40 GiB (block) |

LINSTOR replicates PVCs across both workers (`autoPlace: 2`). Each worker's
`lvm-pool` (`linstor-vg/linstor-thin`) currently holds ~7 GiB total, ~6 GiB free.
The control-plane node is diskless for LINSTOR.

## Storage

- **Ephemeral (node):** ~21 GiB per VM, `DiskPressure=False` observed.
- **LINSTOR thin pool:** ~7 GiB per worker (`lvm-pool`). Plan for PVC growth; current
  total requested across PVCs is ~4.7 GiB (×2 replicas on disk).
- **Second block device per worker** is mandatory for LINSTOR (see `docs/linstor.md`).

## Scaling factors (why RAM matters)

Memory is the binding constraint, not CPU (observed 16–31% CPU). Heavy consumers:

| Component                          | RAM (observed)           |
| ---------------------------------- | ------------------------ |
| kube-apiserver (CP)                | ~2.2 GiB                 |
| argocd-application-controller      | ~1.0 GiB                 |
| prometheus (kube-prometheus-stack) | ~0.6 GiB + 1 GiB request |
| linstor-controller                 | ~0.5 GiB                 |
| vault                              | ~0.4 GiB                 |
| cilium (×3) + envoy                | ~0.9 GiB                 |
| grafana / alloy / others           | ~0.5 GiB                 |

A full rollout (all Argo CD apps running) needs ~11.5 GiB of pod memory. With 13.67 GiB
allocated to VMs on a 15 GiB host, the system swaps. To run **everything** comfortably
(including monitoring) the host needs ~22–24 GiB RAM and VM sizes of CP 6 GiB / workers 8 GiB.

## Notes

- Reducing the CRD count (currently 147) directly lowers apiserver memory.
- Prefer increasing host RAM over shrinking VMs when workloads don't fit.
- Run `free -m` on the Incus host (not inside a VM) to check for swap pressure.
