# Incus Management Guide

> Wrapper/glue layer for the Talos + LINSTOR cluster on a single Gentoo host.

## Architecture

```
┌─────────────────────────────────────────────┐
│                incusbr0                      │
│    10.200.10.1/24 (NAT → wlp1s0)            │
│    DHCP disabled (static IPs in Talos)       │
│    iptables MASQUERADE for outbound access   │
├─────────────────────────────────────────────┤
│  cp-1 (10.200.10.11)   wrk-1 (10.200.10.12) │
│  wrk-2 (10.200.10.13)                       │
│  Control plane + 2 workers                  │
│  All VMs: Talos Linux 1.11.2 + DRBD         │
└─────────────────────────────────────────────┘
```

---

## Quick Reference

### Host Management

```bash
# Service
sudo rc-service incus start     # start daemon
sudo rc-service incus stop      # stop (not containers)
sudo rc-service incus restart   # restart
sudo rc-update add incus default  # enable on boot

# Groups (user needs both)
# hash is in: incus, incus-admin
# After group change: newgrp incus-admin
sg incus-admin -c "sg incus -c 'incus list'"
```

### Image Management

```bash
# List imported images
incus image list

# Import Talos qcow2 (with DRBD)
incus image import /tmp/talos-drbd.qcow2 --alias talos-1.11.2-drbd

# Import from URL (if supported)
incus image import <URL> --alias talos-1.11.2-drbd

# Remove an image
incus image delete <alias|fingerprint>

# Show image details (type, os, release)
incus image show <alias|fingerprint>
```

#### Talos-specific: Seed ISO instead of user.user-data

Incus on this version does **not** read `user.user-data` for VMs.
Machine config is passed via a seed ISO (cidata volume):

```bash
cp controlplane.yaml seed/user-data
echo -e "instance-id: cp-1\nlocal-hostname: cp-1" > seed/meta-data
xorriso -as mkisofs -r -V cidata -J -o seed.iso seed/

incus launch talos-1.11.2-drbd cp-1 --vm \
  -c security.secureboot=false \
  -c "raw.qemu=-drive file=$PWD/seed.iso,if=none,id=drive-cd,format=raw,readonly=on \
        -device virtio-scsi-pci,id=scsi1 -device scsi-cd,drive=drive-cd" \
  -n incusbr0
```

### Instance Lifecycle

```bash
# List instances
incus list
incus list --project <name>

# Create VM from image
incus instance create <image> <name> --type=virtual-machine \
  -c security.secureboot=false \
  -c user.user-data="$(cat machine-config.yaml)" \
  -n incusbr0 \
  -s default

# Start / Stop / Restart
incus start <name>
incus stop <name>
incus restart <name>

# Delete (must be stopped first)
incus stop <name> --force
incus delete <name>

# Shell access (Talos: use talosctl, not incus exec)
incus console <name>     # serial console
incus exec <name> -- <cmd>  # only for containers, not Talos VMs

# View logs / state
incus info <name>
incus info <name> --show-log
```

### Network

```bash
# List networks
incus network list

# Show bridge info
incus network show incusbr0

# Attach additional NIC (if needed)
incus instance device add <name> eth1 nic network=incusbr0

# Detach NIC
incus instance device remove <name> eth1
```

### Profiles

```bash
# List
incus profile list

# Show profile
incus profile show <name>

# Create profile
cat > profile.yaml << 'EOF'
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
EOF
incus profile create talos-vm < profile.yaml

# Apply profile to instance
incus instance assign <name> <profile1>,<profile2>

# Edit profile
incus profile edit <name>
```

### Storage

```bash
# List storage pools
incus storage list

# Show pool info
incus storage show default

# Add LINSTOR data disk to instance
incus instance device add <name> linstor-disk disk \
  pool=default \
  path=/dev/sdb \
  size=10GiB
```

### Snapshots

```bash
# Create snapshot
incus snapshot create <name> <snapshot-name>

# List snapshots
incus snapshot list <name>

# Restore snapshot (instance must be stopped)
incus stop <name>
incus snapshot restore <name> <snapshot-name>

# Delete snapshot
incus snapshot delete <name> <snapshot-name>
```

### Resource Limits

**Minimum memory for Talos control-plane: 2GiB**
The kube-apiserver requires ~254MB contiguous RAM. With default 870MB, admission
denies the pod. Always set `limits.memory=2GiB` for control-plane VMs.

```bash
# Set CPU/memory on running instance
incus instance set <name> limits.cpu=2
incus instance set <name> limits.memory=2GiB

# View current limits
incus instance show <name> | grep -A2 limits
```

### Projects

```bash
# List projects
incus project list

# Current project
incus project switch <name>

# Create project for cluster isolation
incus project create talos \
  -c features.images=true \
  -c features.profiles=true \
  -c features.storage.volumes=false
```

---

## Troubleshooting

### Bridge dnsmasq conflicts with network manager

If port 53 is already in use, disable dnsmasq on the bridge:

```bash
incus network set incusbr0 ipv4.dhcp=false
incus network set incusbr0 dns.mode=none
```

### VM not getting IP

Talos uses **static IPs** — check machine config:

```bash
ip addr show eth0
```

If DHCP is needed temporarily:

```bash
incus network set incusbr0 ipv4.dhcp=true
```

### DHCP helper (dnsmasq) for faster IP assignment

Talos `NodeIPController` starts ~18s after boot, but static IP on virtio-net
takes ~20s — a race condition. DHCP gives an IP in ~5s, bypassing the race.
Run dnsmasq on the host as a bootstrapping helper:

```bash
sudo dnsmasq --interface=incusbr0 --dhcp-range=10.200.10.50,10.200.10.99,12h \
  --dhcp-option=3,10.200.10.1 --port=0 --bind-interfaces &
```

After the node gets its static IP (from Talos config), the DHCP lease is
ignored. Safe to leave running or kill after bootstrap.

### Bridge NAT stops working

Check iptables rules:

```bash
sudo iptables -t nat -L POSTROUTING -v -n
```

Re-add masquerade if missing:

```bash
sudo iptables -t nat -A POSTROUTING -s 10.200.10.0/24 -o wlp1s0 -j MASQUERADE
sudo iptables -A FORWARD -i incusbr0 -o wlp1s0 -j ACCEPT
sudo iptables -A FORWARD -i wlp1s0 -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

### Image import fails: "unknown type"

Incus needs the image to be a VM image. After import, set the type manually:

```bash
incus image show <fingerprint>
# If type is container, try:
incus image import <file> --alias my-vm
# Or create metadata.yaml and re-import as directory
```

### Cannot connect via incus exec

Talos is an immutable OS. Use `talosctl` instead:

```bash
talosctl -n 10.200.10.11 version
talosctl -n 10.200.10.11 dashboard
```

---

## Persistent Setup (Gentoo init scripts)

The bridge and NAT rules need to survive reboots. On Gentoo:

### `/etc/init.d/incus-bridge`

```bash
#!/sbin/openrc-run
description="Incus bridge incusbr0 with NAT"

depend() {
  need net
  after incus
}

start() {
  ebegin "Setting up incusbr0"
  ip link add incusbr0 type bridge 2>/dev/null || true
  ip addr add 10.200.10.1/24 dev incusbr0 2>/dev/null || true
  # Also add FORWARD rules for singtun (VPN interface) if present
  ip link set incusbr0 up
  iptables -t nat -C POSTROUTING -s 10.200.10.0/24 -o wlp1s0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.200.10.0/24 -o wlp1s0 -j MASQUERADE
  iptables -C FORWARD -i incusbr0 -o wlp1s0 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i incusbr0 -o wlp1s0 -j ACCEPT
  iptables -C FORWARD -i wlp1s0 -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i wlp1s0 -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  sysctl -w net.ipv4.ip_forward=1
  eend $?
}

stop() {
  ebegin "Tearing down incusbr0"
  iptables -t nat -D POSTROUTING -s 10.200.10.0/24 -o wlp1s0 -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -i incusbr0 -o wlp1s0 -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i wlp1s0 -o incusbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  ip link set incusbr0 down
  ip link delete incusbr0 2>/dev/null || true
  eend $?
}
```

```bash
sudo chmod +x /etc/init.d/incus-bridge
sudo rc-update add incus-bridge default
```
