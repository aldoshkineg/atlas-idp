# LINSTOR / Piraeus Datastore on Talos Linux

## Why Two Helm Charts

The Piraeus ecosystem is split into two separate Helm charts because of a **CRD ordering constraint**:

| Chart                         | Purpose           | Provides                                                                         |
| ----------------------------- | ----------------- | -------------------------------------------------------------------------------- |
| `piraeus-operator` (OCI)      | Operator + CRDs   | `piraeus-operator-controller-manager`, `LinstorSatellite` CRD, `LinstorNode` CRD |
| `linstor-cluster` (Helm repo) | Cluster resources | `LinstorCluster`, `LinstorSatelliteConfiguration`, `StorageClass`                |

The `linstor-cluster` chart creates resources that depend on CRDs installed by the operator. Using a single chart would require bundling the CRDs inside the cluster chart, which is not how the upstream distributes them. The operator chart is published as an OCI artifact; the `linstor-cluster` chart is a separate Helm chart from the `piraeus-datastore` Helm repository.

This two-chart approach also allows:

- Upgrading the operator independently of the cluster configuration
- Using the same operator with multiple `linstor-cluster` releases (not used here, but architecturally possible)
- Clean separation: the operator is infrastructure, the cluster resources are configuration

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  piraeus-operator chart                             │
│  ┌───────────────────────────────────────────────┐  │
│  │  Operator (controller-manager)                │  │
│  │  Watches: LinstorCluster, LinstorSatellite,   │  │
│  │           LinstorSatelliteConfiguration       │  │
│  └───────────────────────────────────────────────┘  │
│  CRDs: linstorclusters, linstorsatellites,          │
│        linstorsatelliteconfigurations, ...          │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  linstor-cluster chart                              │
│  ┌───────────────────────────────────────────────┐  │
│  │  LinstorCluster (controller, CSI, affinity)   │  │
│  ├───────────────────────────────────────────────┤  │
│  │  LinstorSatelliteConfiguration (patches +     │  │
│  │  storage pools for Talos workers)             │  │
│  ├───────────────────────────────────────────────┤  │
│  │  StorageClass (linstor-replicated, 2 replicas)│  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Talos-Specific Configuration

Talos Linux has no systemd, a read-only `/etc/`, and uses the `siderolabs/drbd` system extension instead of `drbd-module-loader`. Patches in `LinstorSatelliteConfiguration` handle these differences:

### Removed Components

| Component                 | Type           | Reason                          |
| ------------------------- | -------------- | ------------------------------- |
| `drbd-module-loader`      | init container | DRBD loaded via Talos extension |
| `drbd-shutdown-guard`     | init container | Requires systemd                |
| `lib-modules`             | volume         | Read-only `/lib` on Talos       |
| `usr-src`                 | volume         | Read-only `/usr/src` on Talos   |
| `run-systemd-system`      | volume         | No systemd on Talos             |
| `run-drbd-shutdown-guard` | volume         | No systemd on Talos             |
| `systemd-bus-socket`      | volume         | No systemd on Talos             |

### Redirected Paths

| Default            | Talos                  | Reason              |
| ------------------ | ---------------------- | ------------------- |
| `/etc/lvm`         | `/var/etc/lvm`         | `/etc` is read-only |
| `/etc/lvm/archive` | `/var/etc/lvm/archive` | `/etc` is read-only |
| `/etc/lvm/backup`  | `/var/etc/lvm/backup`  | `/etc` is read-only |

### Patch Mechanism

Patches use **strategic merge** (`$patch: delete`) rather than JSON 6902 patches, because strategic merge works on object name matching while JSON patch indices are fragile and break when the operator changes its DaemonSet template order.

Patches are defined in `LinstorSatelliteConfiguration`, not `LinstorCluster`. Cluster-level patches (`LinstorCluster.spec.patches`) exist in the CRD but are **not** propagated to `LinstorSatellite` resources in operator v2.10.x. Only `LinstorSatelliteConfiguration.spec.patches` are applied to the DaemonSet template.

## Installation

### Prerequisites

- Talos cluster with workers
- `/dev/sdb` available on each worker for the LVM storage pool
- `siderolabs/drbd` system extension installed on all nodes
- Helm CLI

### Namespace

Helm's `--create-namespace` flag creates namespaces without labels. The Piraeus datastore requires `privileged` pod security labels, so the namespace is created separately:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: piraeus-datastore
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
EOF
```

### Step 1: Install Operator

```bash
helm upgrade --install piraeus-operator \
  oci://ghcr.io/piraeusdatastore/piraeus-operator/piraeus \
  --version 2.10.6 \
  --namespace piraeus-datastore \
  --values gitops/platform/storage/values/operator-values.yaml \
  --wait

kubectl wait --for=condition=Available deployment/piraeus-operator-controller-manager \
  -n piraeus-datastore --timeout=120s
```

### Step 2: Install Cluster Resources

```bash
helm repo add piraeus-datastore https://piraeusdatastore.github.io/helm-charts 2>/dev/null

helm upgrade --install linstor-cluster \
  piraeus-datastore/linstor-cluster \
  --version 1.1.1 \
  --namespace piraeus-datastore \
  --values gitops/platform/storage/values/linstor-cluster-values.yaml \
  --wait
```

### CRD Workaround

On some installations, the `linstorsatellites.piraeus.io` CRD is not installed by the operator chart. If the operator fails with:

```
the server could not find the requested resource (patch linstorsatellites.piraeus.io <node>)
```

Extract and apply the CRD manually:

```bash
helm template piraeus-operator oci://ghcr.io/piraeusdatastore/piraeus-operator/piraeus \
  --version 2.10.6 --namespace piraeus-datastore \
  --values gitops/platform/storage/values/operator-values.yaml > /tmp/piraeus-rendered.yaml

awk '/^---$/{f=0} /name: linstorsatellites.piraeus.io/{f=1} f' /tmp/piraeus-rendered.yaml \
  > /tmp/linstorsatellites-crd.yaml
kubectl apply -f /tmp/linstorsatellites-crd.yaml
```

## Configuration Reference

All configuration:

| File                                                         | Chart                         |
| ------------------------------------------------------------ | ----------------------------- |
| `gitops/platform/storage/values/operator-values.yaml`        | `piraeus-operator` (OCI)      |
| `gitops/platform/storage/values/linstor-cluster-values.yaml` | `linstor-cluster` (Helm repo) |

### LinstorCluster

| Component                  | Enabled | Notes                       |
| -------------------------- | ------- | --------------------------- |
| controller                 | yes     | LINSTOR controller          |
| csiController              | yes     | CSI controller plugin       |
| csiNode                    | yes     | CSI node plugin             |
| affinityController         | yes     | DRBD affinity scheduling    |
| highAvailabilityController | no      | Not needed for this cluster |

### Storage Pools

- **Name:** `lvm-pool`
- **Type:** LVM
- **Volume Group:** `linstor-vg`
- **Device:** `/dev/sdb` on each worker
- **Size:** depends on `/dev/sdb` disk size on each worker (5.4 GiB per node in stage)

### StorageClass

- **Name:** `linstor-replicated` (default)
- **Provisioner:** `linstor.csi.linbit.com`
- **Replicas:** 2 (`autoPlace: "2"`)
- **Volume Binding:** `WaitForFirstConsumer`
- **Reclaim Policy:** `Delete`
- **Expansion:** allowed

## Verification

```bash
# Cluster status
kubectl get linstorcluster
kubectl get linstorsatellites -o wide
kubectl get pods -n piraeus-datastore

# LINSTOR CLI
alias linstor="kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor"
linstor node list
linstor storage-pool list
linstor resource list
linstor volume list

# End-to-end test
kubectl create ns test-linstor
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: test-linstor
spec:
  storageClassName: linstor-replicated
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: test-linstor
spec:
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-pvc
  restartPolicy: Never
EOF

kubectl wait --for=condition=Ready pod/test-pod -n test-linstor --timeout=30s
kubectl exec -n test-linstor test-pod -- sh -c \
  'echo "hello world" > /data/test.txt && cat /data/test.txt'

# Cleanup
kubectl delete ns test-linstor
```

## Known Issues

1. **Missing `linstorsatellites.piraeus.io` CRD** on fresh installs — workaround: extract and apply manually (see above)
2. **`LinstorCluster.spec.patches` not propagated** to `LinstorSatellite` — operator bug in v2.10.x; patches must go in `LinstorSatelliteConfiguration`
3. **`/var/etc/lvm/` directories** must exist on worker nodes before satellite pods start (created by `DirectoryOrCreate` hostPath type)
4. **`WaitForFirstConsumer`** requires a pod to trigger PVC binding — an unscheduled PVC will remain Pending
