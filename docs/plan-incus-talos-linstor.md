# Implementation Plan: Incus → Talos → LINSTOR → Terraform

**Context:** 1 physical host → Incus → Talos VMs → LINSTOR/Kubernetes.
**Goal:** Production-like environment as close to multi-host as possible, with proper LINSTOR/DRBD testing.

---

## Bootstrap Debugging (Resolved)

Bootstrapping Talos 1.11.2 on Incus VMs hit a permanent `Waiting for etcd spec` block.
Root cause chain found by reading Talos controller source code (`controller-runtime`):

```
AddressStatus: 10.100.10.11/24 (global, valid)
       ↓
NodeAddress routed: [10.100.10.11/24]
       ↓
NodeAddress routed-no-k8s: []  ← EMPTY!
       ↓
NodeIPController (watches routed-no-k8s)
       ↓
"no suitable node IP found"
       ↓
KubeletSpec not created
       ↓
LocalAffiliateController addresses=[]
       ↓
EtcdSpec not created
       ↓
"Waiting for etcd spec"
```

**Root cause:** The `NodeAddressFilterNoK8s` excludes addresses matching
pod CIDR (`10.244.0.0/16`) and service CIDR (`10.96.0.0/12`).
`10.100.10.0/24` falls **inside** `10.96.0.0/12` (`10.96.0.0 – 10.111.255.255`),
so all addresses were filtered out of the `*-no-k8s` variants.
`NodeIPController` watches `routed-no-k8s` → empty → no node IP.

**Fix:** Use a non-overlapping subnet. `10.200.10.0/24` is outside all defaults.

### Validated Bootstrap Commands

```bash
# --- Network ---
sudo ip link add incusbr0 type bridge
sudo ip addr add 10.200.10.1/24 dev incusbr0
sudo ip link set incusbr0 up
# NAT outbound (host has WiFi+VPN — iptables required)
sudo iptables -I FORWARD 1 -i incusbr0 -o wlp1s0 -j ACCEPT
sudo iptables -I FORWARD 2 -i wlp1s0 -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I FORWARD 1 -i incusbr0 -o singtun -j ACCEPT
sudo iptables -I FORWARD 2 -i singtun -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.200.10.0/24 -o wlp1s0 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.200.10.0/24 -o singtun -j MASQUERADE
# DHCP server for fast IP assignment (optional but recommended)
sudo dnsmasq --interface=incusbr0 --dhcp-range=10.200.10.50,10.200.10.99,12h \
  --dhcp-option=3,10.200.10.1 --port=0 --bind-interfaces &

# --- Config generation ---
talosctl gen config test-cluster https://10.200.10.11:6443 \
  --additional-sans 10.200.10.11 --output-dir ./gen

# --- Machine config (YAML snippet) ---
machine:
  network:
    interfaces:
      - deviceSelector: { busPath: "0*" }    # вместо interface: eth0
        dhcp: false
        addresses:
          - 10.200.10.11/24
        routes:
          - network: 0.0.0.0/0
            gateway: 10.200.10.1
  kubelet:
    nodeIP:
      validSubnets:
        - 10.200.10.0/24

# --- Seed ISO (работает на этой версии Incus, user.user-data — нет) ---
mkdir -p seed && cp gen/controlplane.yaml seed/user-data
echo -e "instance-id: test-cp-1\nlocal-hostname: test-cp-1" > seed/meta-data
xorriso -as mkisofs -r -V cidata -J -o seed.iso seed/

incus launch talos-1.11.2-drbd test-cp-1 --vm \
  -c security.secureboot=false \
  -c "raw.qemu=-drive file=$PWD/seed.iso,if=none,id=drive-cd,format=raw,readonly=on -device virtio-scsi-pci,id=scsi1 -device scsi-cd,drive=drive-cd"

# --- Bootstrap ---
talosctl --talosconfig gen/talosconfig -n 10.200.10.11 -e 10.200.10.11 bootstrap
talosctl --talosconfig gen/talosconfig -n 10.200.10.11 -e 10.200.10.11 kubeconfig kubeconfig
kubectl --kubeconfig kubeconfig get nodes

# --- Diagnostics (если bootstrap застрял) ---
talosctl -n <IP> get addressstatus          # адреса есть?
talosctl -n <IP> get nodeaddresses          # routed-no-k8s не пуст?
talosctl -n <IP> logs controller-runtime | grep -i "no suitable"
talosctl -n <IP> get kubeletspecs           # создан?
talosctl -n <IP> get members                # addresses не пуст?
talosctl -n <IP> get etcdspec               # создан?
```

### Key Bootstrap Insights

1. **`10.100.10.0/24` overlaps `10.96.0.0/12`** — always verify
2. **`deviceSelector: {busPath: "0*"}`** надёжнее `interface: eth0` (имя может меняться)
3. **Seed ISO** — единственный рабочий способ передать конфиг в Incus VM (на этой версии)
4. **`NodeIPController`** в Talos 1.11.2 смотрит `routed-no-k8s`, а не `default`/`current`
5. **Race condition:** `NodeIPController` стартует раньше статического IP (разница ~20с в Incus VM из-за virtio-net). DHCP (dnsmasq на хосте) даёт IP за ~5с и обходит race.
6. **VM memory:** Default 870MB недостаточно для kube-apiserver (~254MB). Установить `limits.memory=2GiB`.
7. **Bootstrap persistence:** `talosctl bootstrap` переживает остановку/запуск VM. После `bootstrap` и старта apiserver нода регистрируется автоматически.

---

## 1. Architecture

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                  1 Physical Host (WiFi wlp1s0)                  │
 │                                                                 │
 │  ┌─────────────────────────────────────────────────────────┐    │
 │  │                      Incus                              │    │
 │  │  ┌──────┐  ┌──────┐  ┌────────┐                        │    │
 │  │  │ cp-1 │  │ wrk-1│  │ wrk-2  │                        │    │
 │  │  └──┬───┘  └──┬───┘  └───┬────┘                        │    │
 │  │     │         │          │                              │    │
 │  │     └─────────┴──────────┘                              │    │
 │  │              incusbr0 (managed NAT bridge)              │    │
 │  └─────────────────────────────────────────────────────────┘    │
 │                                                                 │
 │  ┌─────────────────────────────────────────────────────────┐    │
 │  │                    Terraform                             │    │
 │  │  incus  +  helm  +  kubernetes  +  talos  providers     │    │
 │  └─────────────────────────────────────────────────────────┘    │
 └─────────────────────────────────────────────────────────────────┘
```

### Components

| Layer      | Technology          | Purpose                             |
| ---------- | ------------------- | ----------------------------------- |
| Hypervisor | Incus               | VMs for Talos, bridge br0           |
| Cluster OS | Talos Linux         | 1 cp + 2 worker                     |
| CNI        | Cilium              | No kube-proxy, LB IPAM, L2 ann.     |
| Storage    | Piraeus/DRBD        | LINSTOR + CSI + DRBD (replica: 1-2) |
| Ingress    | Gateway API         | L2 address ingress                  |
| Monitoring | Hubble + Prometheus | Network visibility + metrics        |
| IaC        | Terraform           | Full lifecycle                      |

---

## 2. Implementation Phases

### Phase 0: Host Preparation

**Note:** This host uses WiFi (wlp1s0), so a NAT bridge (incusbr0) is used instead of a physical interface bridge. VMs get IPs from a private range and the host provides NAT/masquerading for outbound access. Cilium L2 announcements work within the bridge network.

**WARNING:** Do NOT use `10.100.10.0/24` — it overlaps with the default Kubernetes service CIDR `10.96.0.0/12` (`10.96.0.0–10.111.255.255`). Use `10.200.10.0/24` instead.

```bash
# Incus (Gentoo)
emerge --ask app-containers/incus
gpasswd -a hash incus
incus admin init --auto --network-address=::: --trust-password=admin

# Bridge is created manually (ip tool), NOT via incus network create
# (managed incus bridge had nftables issues on this host)
sudo ip link add incusbr0 type bridge
sudo ip addr add 10.200.10.1/24 dev incusbr0
sudo ip link set incusbr0 up

# iptables rules for NAT — see "Validated Bootstrap Commands" above
```

**Host prerequisites:**

- Incus >= 6.x
- Terraform >= 1.9 or OpenTofu >= 1.8
- `talosctl`, `kubectl`, `helm`

### Phase 1: Custom Talos Image with DRBD

Talos does not include DRBD. Build a custom image via the Image Factory.

**Schematic:**

```json
{
  "customization": {
    "systemExtensions": {
      "officialExtensions": ["siderolabs/drbd"]
    }
  }
}
```

**Confirmed schematic for Talos 1.11.2:**

```
SCHEMATIC_ID=e048aaf4461ff9f9576c9a42f760f2fef566559bd4933f322853ac291e46f238
```

**Get schematic ID for other versions:**

```bash
SCHEMATIC_ID=$(curl -s -X POST https://factory.talos.dev/schematics \
  -H "Content-Type: application/json" \
  -d '{"customization":{"systemExtensions":{"officialExtensions":["siderolabs/drbd"]}}}' | jq -r '.id')

INSTALLER_IMAGE="factory.talos.dev/installer/${SCHEMATIC_ID}:v1.11.2"
```

**Verify DRBD after install:**

```bash
talosctl -n <IP> read /proc/modules | grep drbd
```

### Phase 2: Incus VMs for Talos

**Incus profile (incusbr0, no cloud-init):**

```yaml
name: talos-vm
devices:
  root:
    path: /
    pool: default
    size: 20GiB
    type: disk
  eth0:
    name: eth0
    network: incusbr0
    type: nic
  linstor-disk:
    path: /dev/sdb
    pool: default
    size: 10GiB
    type: disk
```

**Important:** Talos does not use cloud-init. On this Incus version, `user.user-data`
is not read for VMs. Use a **seed ISO** (cidata volume) instead — see Phase 3.

**Machine config for control-plane (cp-1):**

```yaml
version: v1alpha1
machine:
  type: controlplane
  install:
    image: factory.talos.dev/installer/<SCHEMATIC_ID>:v1.11.2
    disk: /dev/sda
  kernel:
    modules:
      - name: drbd
        parameters:
          - usermode_helper=disabled
      - name: drbd_transport_tcp
  network:
    interfaces:
      - deviceSelector: { busPath: "0*" } # вместо interface: eth0
        addresses:
          - 10.200.10.11/24 # вне 10.96.0.0/12!
        routes:
          - network: 0.0.0.0/0
            gateway: 10.200.10.1
  kubelet:
    nodeIP:
      validSubnets:
        - 10.200.10.0/24
cluster:
  clusterName: atlas-linstor
  controlPlane:
    endpoint: https://10.200.10.10:6443 # VIP (kube-vip)
  network:
    cni:
      name: none # Cilium вместо flannel
    dnsDomain: cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true # Cilium берет на себя
```

**Machine config for workers (wrk-1, wrk-2):**

```yaml
version: v1alpha1
machine:
  type: worker
  install:
    image: factory.talos.dev/installer/<SCHEMATIC_ID>:v1.11.2
    disk: /dev/sda
  kernel:
    modules:
      - name: drbd
        parameters:
          - usermode_helper=disabled
      - name: drbd_transport_tcp
  network:
    interfaces:
      - deviceSelector: { busPath: "0*" }
        addresses:
          - 10.200.10.1X/24
        routes:
          - network: 0.0.0.0/0
            gateway: 10.200.10.1
  kubelet:
    nodeIP:
      validSubnets:
        - 10.200.10.0/24
cluster:
  clusterName: atlas-linstor
  controlPlane:
    endpoint: https://10.200.10.10:6443 # VIP (kube-vip)
  network:
    cni:
      name: none
    dnsDomain: cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true
```

### Phase 3: Seed ISO

Incus на этой версии не читает `user.user-data` для VMs. Конфиг передаётся через
seed ISO (cidata):

```bash
rm -rf seed && mkdir seed
cp cp.yaml seed/user-data
echo -e "instance-id: cp-1\nlocal-hostname: cp-1" > seed/meta-data
xorriso -as mkisofs -r -V cidata -J -o seed.iso seed/

incus launch talos-1.11.2-drbd cp-1 --vm \
  -c security.secureboot=false \
  -c "raw.qemu=-drive file=$PWD/seed.iso,if=none,id=drive-cd,format=raw,readonly=on \
        -device virtio-scsi-pci,id=scsi1 -device scsi-cd,drive=drive-cd" \
  -n incusbr0
```

### Phase 4: Talos Bootstrap

```bash
# Generate secrets bundle with VIP
talosctl gen config atlas-linstor https://10.200.10.10:6443

# Apply config to cp-1 (seed ISO, см. Phase 3)

# Bootstrap
talosctl bootstrap --nodes 10.200.10.11 -e 10.200.10.11

# Get kubeconfig (via cp-1 IP, потом поправить endpoint на VIP)
talosctl kubeconfig -n 10.200.10.11 -e 10.200.10.11
sed -i 's/10.200.10.11/10.200.10.10/g' kubeconfig  # заменить на VIP

# Apply config to workers (тоже seed ISO)
```

### Phase 5: Cilium + Hubble

```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set l2announcements.enabled=true \
  --set loadBalancer.algorithm=maglev \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

**L2AnnouncementPolicy:**

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/control-plane: ""
  interfaces:
    - eth0
  externalIPs: true
  loadBalancerIPs: true
```

**LB IPPool:**

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: lb-pool
spec:
  blocks:
    - start: 10.200.10.200
      stop: 10.200.10.220
```

### Phase 6: LINSTOR (Piraeus Operator)

**Install:**

```bash
helm repo add piraeus https://piraeus.io/helm-charts/
helm install piraeus-op piraeus/piraeus \
  --namespace piraeus-system --create-namespace \
  --set operator.controllerReplicas=1
```

**LinstorSatelliteConfiguration (Talos — no systemd):**

```yaml
apiVersion: piraeus.io/v1
kind: LinstorSatelliteConfiguration
metadata:
  name: talos-loader-override
spec:
  podTemplate:
    spec:
      initContainers:
        - name: drbd-shutdown-guard
          $patch: delete
        - name: drbd-module-loader
          $patch: delete
      volumes:
        - name: run-systemd-system
          $patch: delete
        - name: run-drbd-shutdown-guard
          $patch: delete
        - name: systemd-bus-socket
          $patch: delete
        - name: lib-modules
          $patch: delete
        - name: usr-src
          $patch: delete
        - name: etc-lvm-backup
          hostPath:
            path: /var/etc/lvm/backup
            type: DirectoryOrCreate
        - name: etc-lvm-archive
          hostPath:
            path: /var/etc/lvm/archive
            type: DirectoryOrCreate
```

**StoragePool on each worker:**

```bash
kubectl exec -it -n piraeus-system deploy/linstor-controller -- \
  linstor storage-pool create lvm wrk-1 lvm-pool /dev/sdb
kubectl exec -it -n piraeus-system deploy/linstor-controller -- \
  linstor storage-pool create lvm wrk-2 lvm-pool /dev/sdb
```

**StorageClass:**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: linstor-replicated
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
parameters:
  autoPlace: "2" # replica=2 — test degradation
  storagePool: lvm-pool
```

### Phase 7: Terraform Modules

```
infra/
├── environments/
│   ├── dev/                     # existing (kind + ArgoCD)
│   └── stage/                   # new: Talos + LINSTOR on Incus
│       ├── main.tf              # root module
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── talos/
│           ├── cp.yaml          # controlplane machine config
│           └── worker.yaml      # worker machine config
└── modules/
    ├── incus/                   # Networks, projects, Incus profiles
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── talos/                   # Talos VMs + machine config
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── cilium/                  # Cilium + Hubble + L2 ann. + IP Pool
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── piraeus/                 # LINSTOR + DRBD + StorageClass
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

**Module `incus` (networks + projects):**

```hcl
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.1"
    }
  }
}

resource "incus_project" "talos" {
  name        = var.project_name
  description = "Talos cluster"
  config = {
    "features.images"          = false
    "features.profiles"        = true
    "features.storage.volumes" = false
  }
}

resource "incus_profile" "talos_vm" {
  name    = "talos-vm-${var.cluster_name}"
  project = incus_project.talos.name

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = var.root_disk_size
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      name    = "eth0"
      network = var.network_name
    }
  }

  dynamic "device" {
    for_each = var.data_disks
    content {
      name = "data-${device.key}"
      type = "disk"
      properties = {
        path = device.value.path
        pool = var.storage_pool
        size = device.value.size
      }
    }
  }
}
```

**Module `talos` (VM instances):**

```hcl
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.1"
    }
  }
}

data "incus_project" "talos" {
  name = var.project_name
}

data "incus_profile" "talos_vm" {
  name    = "talos-vm-${var.cluster_name}"
  project = data.incus_project.talos.name
}

resource "incus_instance" "controlplane" {
  count     = var.cp_count
  project   = data.incus_project.talos.name
  name      = "${var.cluster_name}-cp-${count.index + 1}"
  image     = var.talos_image
  type      = "virtual-machine"
  profiles  = [data.incus_profile.talos_vm.name]
  running   = true

  config = {
    "security.secureboot" = false
    "security.secureboot" = false
    # NOTE: seed ISO needed — user.user-data not read on this Incus version
  }

  limits = {
    cpu    = var.cp_cpu
    memory = var.cp_memory
  }
}

resource "incus_instance" "worker" {
  count     = var.worker_count
  project   = data.incus_project.talos.name
  name      = "${var.cluster_name}-worker-${count.index + 1}"
  image     = var.talos_image
  type      = "virtual-machine"
  profiles  = [data.incus_profile.talos_vm.name]
  running   = true

  config = {
    "security.secureboot" = false
    # NOTE: seed ISO needed — user.user-data not read on this Incus version
  }

  limits = {
    cpu    = var.worker_cpu
    memory = var.worker_memory
  }
}
```

**Module `piraeus`:**

```hcl
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }
}

resource "helm_release" "piraeus" {
  name             = "piraeus-op"
  namespace        = "piraeus-system"
  create_namespace = true

  repository = "https://piraeus.io/helm-charts/"
  chart      = "piraeus"
  version    = var.chart_version

  set {
    name  = "operator.controllerReplicas"
    value = "1"
  }
}

resource "kubernetes_manifest" "talos_satellite_config" {
  manifest = {
    apiVersion = "piraeus.io/v1"
    kind       = "LinstorSatelliteConfiguration"
    metadata   = { name = "talos-loader-override" }
    spec = {
      podTemplate = {
        spec = {
          initContainers = [
            { name = "drbd-shutdown-guard", $patch = "delete" },
            { name = "drbd-module-loader",  $patch = "delete" }
          ]
          volumes = [
            { name = "run-systemd-system",     $patch = "delete" },
            { name = "run-drbd-shutdown-guard", $patch = "delete" },
            { name = "systemd-bus-socket",      $patch = "delete" },
            { name = "lib-modules",             $patch = "delete" },
            { name = "usr-src",                 $patch = "delete" },
            {
              name = "etc-lvm-backup"
              hostPath = { path = "/var/etc/lvm/backup", type = "DirectoryOrCreate" }
            },
            {
              name = "etc-lvm-archive"
              hostPath = { path = "/var/etc/lvm/archive", type = "DirectoryOrCreate" }
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "linstor_sc" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata   = { name = "linstor-replicated" }
    provisioner          = "linstor.csi.linbit.com"
    allowVolumeExpansion = true
    parameters = {
      autoPlace   = var.replica_count
      storagePool = var.storage_pool_name
    }
  }
}
```

---

## 3. Complete Workflow

```bash
# 0. Create Incus bridge incusbr0 (one-time on host)
sudo ip link add incusbr0 type bridge
sudo ip addr add 10.200.10.1/24 dev incusbr0
sudo ip link set incusbr0 up
# iptables: NAT + FORWARD (см. "Validated Bootstrap Commands" выше)

# 1. Build seed ISOs for each node
#    (user-data on cidata volume, user.user-data не работает)
./scripts/build-seed-isos.sh

# 2. Launch VMs manually, then bootstrap
talosctl --talosconfig talosconfig -n 10.200.10.11 -e 10.200.10.11 bootstrap
talosctl --talosconfig talosconfig -n 10.200.10.11 -e 10.200.10.11 kubeconfig

# 3. Terraform (future: replace manual steps)
cd infra/environments/stage
tofu init && tofu apply

# 4. kube-vip (если нужна VIP)
kube-vip manifest pod \
  --interface eth0 --address 10.200.10.10 \
  --controlPlane --services --arp --leaderElection

# 5. Preflight
talosctl -n 10.200.10.11 read /proc/modules | grep drbd  # ✓ DRBD loaded
kubectl get nodes                                         # ✓ cluster online
```

---

## 4. Key Differences from Multi-Host Plan

| Component       | Before (multi-host)    | Now (1 host)                    |
| --------------- | ---------------------- | ------------------------------- |
| Control Plane   | 3 cp                   | **1 cp**                        |
| Workers         | 3+                     | **2**                           |
| API endpoint    | kube-vip VIP           | **kube-vip ARP (10.200.10.10)** |
| kube-proxy      | enabled                | **Disabled (Cilium)**           |
| CNI             | flannel                | **Cilium + L2 ann. + Hubble**   |
| LB              | MetalLB                | **Cilium LB IPAM**              |
| DRBD replica    | 3                      | **2 (logical replication)**     |
| Network         | incusbr0 NAT (on WiFi) | **manual bridge incusbr0**      |
| Config delivery | cloud-init             | **seed ISO (cidata volume)**    |

---

## 5. IP Addressing (10.200.10.0/24)

Dedicated `/24` range for the lab cluster, chosen to be **outside** the default
Kubernetes service CIDR (`10.96.0.0/12` — `10.96.0.0` to `10.111.255.255`).

| Role           | IP                | Notes                          |
| -------------- | ----------------- | ------------------------------ |
| kube-vip (VIP) | 10.200.10.10      | API endpoint (kube-vip ARP)    |
| cp-1           | 10.200.10.11      | Control plane                  |
| worker-1       | 10.200.10.12      | Worker + LINSTOR satellite     |
| worker-2       | 10.200.10.13      | Worker + LINSTOR satellite     |
| Gateway        | 10.200.10.1       | Host (Incus bridge, NAT)       |
| LB Pool        | 10.200.10.200–220 | Cilium L2 announcements        |
| DHCP pool      | 10.200.10.50–99   | dnsmasq (bootstrapping helper) |

**Why 10.200.10.0/24:**

- **Outside `10.96.0.0/12`** — no overlap with default k8s service CIDR
- Outside Docker (172.x), VPNs (common 10.0.0.x), home LAN (192.168.x)
- `/24` leaves room for 11 more nodes

---

## 6. Risks

- **DRBD replica=2 on a single physical host:** replication between VMs on the same disk is purely logical. LINSTOR and CSI are tested, but physical fault tolerance is not provided.
- **kube-vip on a single cp:** failover won't happen, but the deployment configuration and procedure are identical to multi-host.
- **Cilium L2 announcements:** work within the managed bridge (incusbr0). Services get LB IPs from the private range (10.200.10.200-220) reachable from the host. No LAN exposure.
- **Disabled kube-proxy:** Cilium `kubeProxyReplacement=true` must work correctly. If issues arise, temporarily re-enable kube-proxy.
- ~~DRBD extension may not be available~~ — **confirmed:** `siderolabs/drbd (9.2.14-v1.11.2)` is available on Image Factory for Talos 1.11. Fallback via local `imager` build only for newer versions not yet in the factory.

---

## 7. Preflight Checklist

```text
✓ Manual bridge incusbr0 (10.200.10.1/24) — iptables NAT ok
✓ Talos image with DRBD (schematic e048aaf44...) — imported
✓ Node IP subnet outside k8s service CIDR (10.200.10.0/24 ∉ 10.96.0.0/12)
✓ routed-no-k8s не пуст (NodeIPController доволен)
✓ Bootstrap → EtcdSpec → etcd → kubelet → apiserver — полная цепочка
✓ Seed ISO — единственный рабочий способ передачи конфига
✓ VM memory: limits.memory=2GiB (иначе apiserver не стартует)
⚠ DRBD module — image импортирован, загрузка не проверена
⚠ Terraform — модули описаны (plan), не реализованы
⚠ Talos cluster — 1 cp запущен, workers не добавлены
⚠ Cilium — не установлен (Flannel по умолчанию)
⚠ Hubble — не установлен
⚠ L2 announcements — не настроены
⚠ Piraeus/LINSTOR — не установлен
⚠ StorageClass — не создан
```

---

## 8. Makefile Targets

```makefile
talos-image-drbd:             # Build image with DRBD via Image Factory
stage-up:                     # tofu apply -chdir=infra/environments/stage
stage-down:                   # tofu destroy -chdir=infra/environments/stage
kube-vip-deploy:              # Deploy kube-vip on cp-1
cilium-install:               # Install Cilium + Hubble + L2
linstor-deploy:               # Install Piraeus operator
linstor-storage-pools:        # Create storage pools on workers
linstor-test-pvc:             # Test PVC + pod
preflight:                    # Run all checklist items
```
