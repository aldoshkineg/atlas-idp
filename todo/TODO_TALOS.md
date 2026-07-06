Before we move on to formulating the final technical specification, let us do a brief engineering review of your stack. The architecture emerges as very powerful — in fact, you are building a full-fledged enterprise cloud in miniature.

### Architectural Analysis of the Stack

1. **Incus + Terraform:** Excellent combination. The `lxc/incus` provider is mature, enabling declarative description of not only VMs but also disks for LINSTOR, as well as the networks where the load balancer will reside.
2. **Terminology Clarification (Important):** The text states _"enable rbd for linstor"_. This is slightly misleading: **RBD** (RADOS Block Device) is a distributed disk protocol from the **Ceph** ecosystem. For **LINSTOR**, the underlying replication technology is **DRBD** (Distributed Replicated Block Device). In the spec below we will use **DRBD** since we are setting up LINSTOR.
3. **Cilium as LoadBalancer:** An excellent choice for bare-metal/VM environments. It allows full elimination of `kube-proxy` (via eBPF) and provides load balancers through **L2 Announcements** (ARP requests) or **BGP**.
4. **Gotcha (Incus Bridge + Cilium L2):** If Cilium announces load balancer IPs via L2 (ARP), the Incus bridge must allow VMs to respond for IP addresses that were not originally assigned to them via Incus DHCP. By default, a managed Incus bridge may block such traffic if security is enabled (`security.mac_filtering` / `security.ipv4_filtering`). In the spec we will ensure the network profile is clean.

---

## System Technical Specification

**Project:** Deployment of a declarative, fault-tolerant Kubernetes cluster based on Talos Linux in an Incus environment using IaC (Terraform).

---

### 1. Virtualization Layer and IaC (Incus & Terraform)

**Goal:** Prepare host infrastructure, create networks, profiles, and virtual machines for the K8s cluster (1 Control Plane, 2 Workers).

#### Incus Configuration Requirements:

- **Network:** Create a dedicated managed bridge (e.g., `incusbr1`) with subnet `10.10.10.0/24`. Disable IP/MAC filtering on ports (`security.ipv4_filtering = false`) so Cilium can freely announce load balancer IPs.
- **Virtual Machine Profile (`talos-vm-profile`):**
- Instance type: `virtual-machine`.
- Enable TPM emulation and SecureBoot (if required by Talos, or disable for simplified testing).
- Control Plane limits: 2 vCPU, 4GiB RAM.
- Worker node limits: 2 vCPU, 4GiB RAM.

- **Disk subsystem for LINSTOR:**
- Each Worker node, in addition to the main system disk (`root`), must have a **second unformatted block device** attached via Terraform (e.g., `/dev/sdb` or an additional disk from the Incus storage pool) of at least 20GiB for LINSTOR satellite needs.

#### Terraform Specification:

- Use the official `lxc/incus` provider.
- Use the `siderolabs/talos` provider for cluster configuration generation (`machineconfig`) and authentication files (`talosconfig`).

---

### 2. OS Layer and Storage (Talos Linux & LINSTOR)

**Goal:** Deploy the immutable Talos OS with kernel replication module support, followed by running distributed storage.

#### Talos Linux Configuration:

- During image generation (via Talos Image Factory) or schema assembly, add the official system kernel extension: **`siderolabs/drbd`** (version 9.x).
- The `machineConfig` for Worker nodes should include activation of the required kernel modules at startup:

```yaml
machine:
  kernel:
    modules:
      - name: drbd
      - name: drbd_transport_tcp
```

#### Piraeus Operator (Helm):

- **Components:** Piraeus Operator version `2.10.x`.
- **Pool configuration:** Configure `LinstorCluster` to use physical disks provisioned from Incus (pool type `lvmThinPool`), targeting the prepared `/dev/sdb`.
- **StorageClass:** Create a default class `linstor-ha` with parameter `autoPlace: "2"` (double synchronous replication between worker nodes).

---

### 3. Network Layer and Load Balancing (Cilium CNI)

**Goal:** Provide Pod-to-Pod network connectivity, fault-tolerant routing, and `LoadBalancer` type services.

#### Talos Configuration for Cilium:

- During Talos deployment, disable the default CNI (`flannel`) by setting `cni.provider: none`.
- Disable `kube-proxy` by passing a deactivation instruction in the cluster configuration, so Cilium handles eBPF routing.

#### Cilium Helm Chart Configuration:

- Operation mode: Native eBPF kube-proxy (kubeProxyReplacement=true).
- **LoadBalancer specification:** Enable **L2 Announcements** and integrate with the address pool.
- **Address pool manifests (`CiliumLoadBalancerIPPool`):** Allocate an IP range from the Incus bridge network (e.g., `10.10.10.200-10.10.10.250`) that does not overlap with the Incus DHCP pool.

---

### 4. Testing Success Criteria (Acceptance Criteria)

1. **Infrastructure:** `terraform apply` completes without errors, creating 3 VMs in Incus connected by a network.
2. **K8s Cluster:** The `talosctl dashboard` command shows status `Healthy`, all nodes are in `Ready` state.
3. **Storage:** LINSTOR satellite pods successfully initialize LVM pools on the secondary VM disks. A test PVC transitions to `Bound` status.
4. **Network:** Creating a `type: LoadBalancer` service for a test application (e.g., `nginx`) successfully allocates an IP from the Cilium pool (e.g., `10.10.10.200`). The application is accessible at that IP directly from the host machine via browser or `curl`.

## 1. IaC Layer: Incus Configuration in Terraform (`main.tf`)

For Cilium L2 Announcements and LINSTOR to work, we need to disable traffic filtering on the Incus network bridge and pass through an additional clean disk to each worker node.

```hcl
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = ">= 0.6.0"
    }
  }
}

# 1. Create an isolated network without IP/MAC filtering
resource "incus_network" "k8s_net" {
  name = "k8sbr0"
  config = {
    "ipv4.address"            = "10.10.10.1/24"
    "ipv4.dhcp"               = "true"
    "ipv4.nat"                = "true"
    "security.ipv4_filtering" = "false" # CRITICAL: allows Cilium to announce LB IPs
    "security.mac_filtering"  = "false"
  }
}

# 2. Create dedicated block volumes in the Incus pool for LINSTOR
resource "incus_storage_volume" "linstor_disk" {
  count        = 2
  name         = "linstor-worker-disk-${count.index + 1}"
  pool         = "default"
  content_type = "block"
  size         = "30GiB"
}

# 3. Example Worker node definition (repeat for each via count/for_each)
resource "incus_instance" "talos_worker" {
  count     = 2
  name      = "talos-worker-${count.index + 1}"
  image     = "talos-drbd-custom-image" # Your image from Talos factory with DRBD extension
  type      = "virtual-machine"
  running   = true

  config = {
    "limits.cpu"    = "2"
    "limits.memory" = "4GiB"
  }

  limits {
    memory = "4GiB"
  }

  # Main OS disk
  device {
    name = "root"
    type = "disk"
    properties = {
      pool = "default"
      path = "/"
    }
  }

  # SECOND DISK FOR LINSTOR (visible in Talos as /dev/vdb)
  device {
    name = "linstor_backend"
    type = "disk"
    properties = {
      pool   = "default"
      source = incus_storage_volume.linstor_disk[count.index].name
    }
  }

  network_interface {
    name = "eth0"
    network = incus_network.k8s_net.name
  }
}

```

---

## 2. OS Layer: Talos Linux Configuration Patches

When generating the cluster configuration via `talosctl gen config` or the `siderolabs/talos` Terraform provider, we need to apply the following patches.

### Patch for Control Plane & Workers (`common.yaml`)

> Disable the default Flannel and load DRBD modules.

```yaml
machine:
  kernel:
    modules:
      - name: drbd
      - name: drbd_transport_tcp
  network:
    cni:
      name: none # Disable default CNI for Cilium
cluster:
  proxy:
    disabled: true # Disable kube-proxy, Cilium will replace it via eBPF
```

---

## 3. Network Layer: Helm values for Cilium

Deploy Cilium without `kube-proxy` with the L2 announcement engine for the load balancer enabled.

### `cilium-values.yaml`

```yaml
kubeProxyReplacement: true
k8sServiceHost: 10.10.10.10 # Specify the static IP of your Control Plane in the Incus network
k8sServicePort: 6443

# Enable LoadBalancer functionality
l2announcements:
  enabled: true

# Force enable traffic redirection
bpf:
  masquerade: true

externalIPs:
  enabled: true
```

### Load balancer address pool manifests (apply after CNI)

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: incus-lb-pool
  namespace: kube-system
spec:
  blocks:
    - cidr: "10.10.10.200/28" # Allocate IPs 10.10.10.200 - 10.10.10.215 for services
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
  namespace: kube-system
spec:
  interfaces:
    - ^eth[0-9] # Announce through the Talos node network interface
  nodeSelector:
    matchExpressions:
      - key: kubernetes.io/os
        operator: In
        values:
          - linux
```

---

## 4. Storage Layer: Pool initialization in LINSTOR

**Superseded** — the current LINSTOR configuration lives in:

- Values: `gitops/platform-kind/layers/storage/linstor/`
- Documentation: `docs/linstor.md`

Key differences from the superseded design below:

- Uses `LinstorSatelliteConfiguration` patches (not `LinstorCluster.spec.patches` — operator bug v2.10.x)
- `LVM` pool (not `LVMThinPool`)
- Volume group `linstor-vg` (not `linstor_vg`)
- Device `/dev/sdb` (not `/dev/vdb`)
- Strategic merge `$patch: delete` for Talos-specific removals (drbd-module-loader, drbd-shutdown-guard, etc.)

See `docs/linstor.md` for installation, verification, and known issues.

---

### Architectural checklist before running `terraform apply`:

1. [ ] You have created a custom Talos Linux image with the `siderolabs/drbd` extension (version 9.x).
2. [ ] You have fixed the IP address for the Control Plane so that Cilium has a hardcoded `k8sServiceHost` in its configuration.
3. [ ] You have verified that the `10.10.10.200/28` subnet for the Cilium load balancer does not overlap with the Incus DHCP server's allocation range.

Which step shall we start with — generate a custom Talos image via the Factory API, or proceed directly to structuring the repository for ArgoCD?
