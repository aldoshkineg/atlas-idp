## 1. Create Docker network with predictable subnet

To get a fixed VIP like `172.20.10.1` for ingress via Cilium in Kind and drop MetalLB, here's the approach.

If the cluster doesn't exist yet:

```bash
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  kind
```

Verification:

```bash
docker network inspect kind
```

Note down:

- subnet
- gateway (usually `172.20.0.1`)

---

## 2. Create Kind without kube-proxy

For Cilium this is preferred.

`kind-config.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

networking:
  disableDefaultCNI: true
  kubeProxyMode: "none"

nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

Creation:

```bash
kind create cluster \
  --name lab \
  --config kind-config.yaml
```

---

## 3. Install Cilium

Example for current versions:

```bash
cilium install \
  --set kubeProxyReplacement=true
```

Verification:

```bash
cilium status --wait
```

All components should be `OK`.

---

## 4. Create LoadBalancer IP pool

For example, allocate a range:

```text
172.20.10.1 - 172.20.10.20
```

Important:

- do not use the gateway;
- do not use node container addresses.

Check occupied IPs:

```bash
docker inspect $(docker ps -q) \
  | grep 172.20.
```

Create pool:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: ingress-pool
spec:
  blocks:
    - start: 172.20.10.1
      stop: 172.20.10.20
```

```bash
kubectl apply -f pool.yaml
```

Verification:

```bash
kubectl get ippools
```

---

## 5. Enable L2 Announcements

The VIP needs an address announcement mechanism.

```bash
cilium upgrade \
  --reuse-values \
  --set l2announcements.enabled=true
```

Create policy:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: ingress
spec:
  serviceSelector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx

  interfaces:
    - eth0

  externalIPs: true
  loadBalancerIPs: true
```

```bash
kubectl apply -f l2-policy.yaml
```

---

## 6. Install ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace
```

---

## 7. Pin the VIP

Patch the service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  loadBalancerIP: 172.20.10.1
```

Apply:

```bash
kubectl apply -f ingress-service.yaml
```

---

## 8. Verify address assignment

```bash
kubectl get svc -n ingress-nginx
```

Expected output:

```text
NAME                       TYPE           EXTERNAL-IP
ingress-nginx-controller   LoadBalancer   172.20.10.1
```

---

## 9. Verify routing

From the host:

```bash
ping 172.20.10.1
```

```bash
curl http://172.20.10.1
```

---

## Final diagram

```text
Docker network
172.20.0.0/16
       |
       +-- kind-control-plane
       +-- kind-worker
       +-- kind-worker2
               |
             Cilium
               |
      LB IPAM + L2 Announcement
               |
          172.20.10.1
               |
        ingress-nginx
```

For a home lab and CI this is currently one of the cleanest setups: Kind + Cilium + LB IPAM + L2 Announcements, without MetalLB at all. The only thing I would add is reserving a separate range like `172.20.250.0/24` for all future LoadBalancer services, so they don't overlap with node addresses. For example:

```text
172.20.250.1   ingress
172.20.250.2   grafana
172.20.250.3   argocd
172.20.250.4   prometheus
```
