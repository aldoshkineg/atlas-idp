## 1. Создать сеть Docker с предсказуемой подсетью

Если цель — получить в Kind фиксированный VIP вида `172.20.10.1` для ingress через Cilium и отказаться от MetalLB, я бы делал так.

Если кластера ещё нет:

```bash
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  kind
```

Проверка:

```bash
docker network inspect kind
```

Запомнить:

- subnet
- gateway (обычно `172.20.0.1`)

---

## 2. Создать Kind без kube-proxy

Для Cilium это предпочтительно.

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

Создание:

```bash
kind create cluster \
  --name lab \
  --config kind-config.yaml
```

---

## 3. Установить Cilium

Пример для актуальных версий:

```bash
cilium install \
  --set kubeProxyReplacement=true
```

Проверка:

```bash
cilium status --wait
```

Все компоненты должны быть `OK`.

---

## 4. Создать пул LoadBalancer IP

Например, выделим диапазон:

```text
172.20.10.1 - 172.20.10.20
```

Важно:

- не использовать gateway;
- не использовать адреса контейнеров нод.

Проверить занятые IP:

```bash
docker inspect $(docker ps -q) \
  | grep 172.20.
```

Создать пул:

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

Проверка:

```bash
kubectl get ippools
```

---

## 5. Включить L2 Announcements

Для VIP нужен механизм анонса адреса.

```bash
cilium upgrade \
  --reuse-values \
  --set l2announcements.enabled=true
```

Создать policy:

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

## 6. Установить ingress-nginx

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

## 7. Зафиксировать VIP

Патч сервиса:

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

Применить:

```bash
kubectl apply -f ingress-service.yaml
```

---

## 8. Проверить выдачу адреса

```bash
kubectl get svc -n ingress-nginx
```

Ожидаемо:

```text
NAME                       TYPE           EXTERNAL-IP
ingress-nginx-controller   LoadBalancer   172.20.10.1
```

---

## 9. Проверить маршрутизацию

С хоста:

```bash
ping 172.20.10.1
```

```bash
curl http://172.20.10.1
```

---

## Итоговая схема

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

Для домашней лаборатории и CI это сейчас одна из самых чистых схем: Kind + Cilium + LB IPAM + L2 Announcements, без MetalLB вообще. Единственное, что я бы сделал дополнительно — зарезервировал отдельный диапазон вроде `172.20.250.0/24` под все будущие LoadBalancer-сервисы, чтобы не пересечься с адресами нод. Например:

```text
172.20.250.1   ingress
172.20.250.2   grafana
172.20.250.3   argocd
172.20.250.4   prometheus
```
