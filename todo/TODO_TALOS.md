Before we move on to formulating the final technical specification, let us do a brief engineering review of your stack. The architecture emerges as very powerful — in fact, you are building a full-fledged enterprise cloud in miniature.

### Architectural Analysis of the Stack

1. **Incus + Terraform:** Отличная связка. Провайдер `lxc/incus` зрелый, позволяет декларативно описать не только виртуалки, но и диски для LINSTOR, а также сети, на которых будет жить балансировщик.
2. **Фиксация терминологии (Важно!):** В тексте указано _«включаем rbd - для linstor»_. Здесь кроется небольшая путаница: **RBD** (RADOS Block Device) — это протокол распределенных дисков из экосистемы **Ceph**. Для **LINSTOR** базовой технологией репликации является **DRBD** (Distributed Replicated Block Device). В системном задании ниже мы зафиксируем именно **DRBD**, так как мы настраиваем LINSTOR.
3. **Cilium как LoadBalancer:** Великолепный выбор для bare-metal/VM сред. Он позволяет полностью отказаться от `kube-proxy` (через eBPF) и давать балансировщики через **L2 Announcements** (ARP-запросы) или **BGP**.
4. **Подводный камень (Incus Bridge + Cilium L2):** Если Cilium будет анонсировать IP-адреса балансировщиков через L2 (ARP), мост Incus должен позволять виртуалкам отвечать за IP-адреса, которые не были им выданы изначально через DHCP Incus. По умолчанию управляемый мост Incus может блокировать такой трафик, если включена безопасность (`security.mac_filtering` / `security.ipv4_filtering`). В ТЗ мы учтем, что сетевой профиль должен быть чистым.

---

## System Technical Specification

**Проект:** Развертывание декларативного отказоустойчивого Kubernetes-кластера на базе Talos Linux в среде Incus с использованием IaC (Terraform).

---

### 1. Virtualization Layer and IaC (Incus ### 1. Virtualization Layer and IaC (Incus ### 1. Слой виртуализации и IaC (Incus & Terraform) Terraform) Terraform)

**Цель:** Подготовка инфраструктуры хоста, создание сетей, профилей и виртуальных машин для кластера K8s (1 Control Plane, 2 Workers).

#### Incus Configuration Requirements:

- **Сеть:** Создать выделенный управляемый мост (например, `incusbr1`) с подсетью `10.10.10.0/24`. Отключить фильтрацию IP/MAC на портах (`security.ipv4_filtering = false`), чтобы Cilium мог свободно анонсировать IP балансировщиков.
- \*\* **Virtual Machine Profile (`talos-vm-profile`):**
- Тип инстанса: `virtual-machine`.
- Включить эмуляцию TPM и SecureBoot (при необходимости для Talos, либо отключить для упрощения тестирования).
- Лимиты для Control Plane: 2 vCPU, 4GiB RAM.
- Лимиты для Worker нод: 2 vCPU, 4GiB RAM.

- **Дисковая подсистема для LINSTOR:**
- Каждой Worker-ноде, помимо основного системного диска (`root`), через Terraform должен быть подключен **второй незанятый блочный девайс** (например, `/dev/sdb` или дополнительный диск из пула хранения Incus) объемом от 20GiB для нужд LINSTOR сателлитов.

#### Terraform Specification:

- Использовать официальный провайдер `lxc/incus`.
- Использовать провайдер `siderolabs/talos` для генерации конфигурации кластера (`machineconfig`) и файлов аутентификации (`talosconfig`).

---

### 2. OS Layer and Storage (Talos Linux ### 2. OS Layer and Storage (Talos Linux ### 2. Слой ОС и Хранилища (Talos Linux & LINSTOR) LINSTOR) LINSTOR)

**Цель:** Развертывание иммутабельной ОС Talos с поддержкой модулей репликации ядра и последующий запуск распределенного хранилища.

#### Talos Linux Configuration:

- На этапе генерации образов (через Talos Image Factory) или сборки схемы добавить официальное системное расширение ядра: **`siderolabs/drbd`** (версии 9.x).
- Конфигурация `machineConfig` для Worker-нод должна содержать активацию необходимых модулей ядра при старте:

```yaml
machine:
  kernel:
    modules:
      - name: drbd
      - name: drbd_transport_tcp
```

Helm):/ Helm):

- **Компоненты:** Piraeus Operator версии `2.10.x`.
- **Конфигурация пула:** Настроить `LinstorCluster` на использование физических дисков, проброшенных из Incus (тип пула `lvmThinPool`), которые смотрят на подготовленный `/dev/sdb`.
- **StorageClass:** Создать дефолтный класс `linstor-ha` с параметром `autoPlace: "2"` (двухкратная синхронная репликация между worker-нодами).

---

### 3. Network Layer and Load Balancing (Cilium CNI)

**Цель:** Обеспечение сетевой связности Pod-to-Pod, отказоустойчивой маршрутизации и предоставление сервисов типа `LoadBalancer`.

#### Talos Configuration for Cilium:

- При развертывании Talos отключить стандартный дефолтный CNI (`flannel`), установив значение `cni.provider: none`.
- Отключить `kube-proxy`, передав в конфигурацию кластера инструкцию по его деактивации, чтобы Cilium взял на себя eBPF-маршрутизацию.

#### Cilium Helm Chart Configuration:

- Режим работы: Нативный eBPF-кубпрокси (kubeProxyReplacement=true).
- **Спецификация LoadBalancer:** Включить модуль **L2 Announcements** и интегрировать его с пулом адресов.
- **Манифесты пула адресов (`CiliumLoadBalancerIPPool`):** Выделить диапазон IP из сети моста Incus (например, `10.10.10.200-10.10.10.250`), который не пересекается с DHCP-пулом самого Incus.

---

### 4. Testing Success Criteria (Acceptance Criteria)

1. **Инфраструктура:** `terraform apply` отрабатывает без ошибок, создавая 3 виртуалки в Incus, связанные сетью.
2. **Кластер K8s:** Команда `talosctl dashboard` показывает статус `Healthy`, все ноды находятся в состоянии `Ready`.
3. **Хранилище:** Поды LINSTOR сателлитов успешно инициализируют LVM-пулы на вторых дисках виртуалок. Тестовый PVC переходит в статус `Bound`.
4. **Сеть:** Создание сервиса `type: LoadBalancer` для тестового приложения (например, `nginx`) успешно выделяет IP из пула Cilium (например, `10.10.10.200`). Приложение доступно по этому IP прямо с хост-машины через браузер или `curl`.

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

# 1. Создаем изолированную сеть без фильтрации IP/MAC
resource "incus_network" "k8s_net" {
  name = "k8sbr0"
  config = {
    "ipv4.address"            = "10.10.10.1/24"
    "ipv4.dhcp"               = "true"
    "ipv4.nat"                = "true"
    "security.ipv4_filtering" = "false" # КРИТИЧНО: разрешает Cilium анонсировать LB IP
    "security.mac_filtering"  = "false"
  }
}

# 2. Создаем выделенные block-тома в Incus пуле для LINSTOR
resource "incus_storage_volume" "linstor_disk" {
  count        = 2
  name         = "linstor-worker-disk-${count.index + 1}"
  pool         = "default"
  content_type = "block"
  size         = "30GiB"
}

# 3. Пример описания Worker-ноды (повторить для каждой через count/for_each)
resource "incus_instance" "talos_worker" {
  count     = 2
  name      = "talos-worker-${count.index + 1}"
  image     = "talos-drbd-custom-image" # Ваш образ с фабрики Talos с DRBD расширением
  type      = "virtual-machine"
  running   = true

  config = {
    "limits.cpu"    = "2"
    "limits.memory" = "4GiB"
  }

  limits {
    memory = "4GiB"
  }

  # Основной диск ОС
  device {
    name = "root"
    type = "disk"
    properties = {
      pool = "default"
      path = "/"
    }
  }

  # ВТОРОЙ ДИСК ДЛЯ LINSTOR (увидится в Talos как /dev/vdb)
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

## 2. Слой ОС: Патчи конфигурации Talos Linux

При генерации конфигурации кластера через `talosctl gen config` или Terraform-провайдер `siderolabs/talos`, нам нужно применить следующие патчи.

### Патч для Control Plane & Workers (`common.yaml`)

> Отключаем дефолтный Flannel и загружаем модули DRBD.

```yaml
machine:
  kernel:
    modules:
      - name: drbd
      - name: drbd_transport_tcp
  network:
    cni:
      name: none # Выключаем дефолтный CNI для Cilium
cluster:
  proxy:
    disabled: true # Выключаем kube-proxy, так как Cilium заменит его через eBPF
```

---

## 3. Сетевой слой: Helm-values для Cilium

Разворачиваем Cilium без `kube-proxy` с включенным движком L2-анонсов балансировщика.

### `cilium-values.yaml`

```yaml
kubeProxyReplacement: true
k8sServiceHost: 10.10.10.10 # Укажите статический IP вашего Control Plane в сети Incus
k8sServicePort: 6443

# Активация функционала LoadBalancer
l2announcements:
  enabled: true

# Принудительно включаем перенаправление трафика
bpf:
  masquerade: true

externalIPs:
  enabled: true
```

### Манифесты пула адресов для балансировщика (применять после CNI)

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: incus-lb-pool
  namespace: kube-system
spec:
  blocks:
    - cidr: "10.10.10.200/28" # Выделяем IP 10.10.10.200 - 10.10.10.215 под сервисы
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
  namespace: kube-system
spec:
  interfaces:
    - ^eth[0-9] # Анонсировать через сетевой интерфейс нод Talos
  nodeSelector:
    matchExpressions:
      - key: kubernetes.io/os
        operator: In
        values:
          - linux
```

---

## 4. Слой хранения: Инициализация пула в LINSTOR

Хотя в иммутабельной ОС Talos нет утилит `lvm2` на хосте, ядро поддерживает device-mapper. Контейнер `linstor-satellite` запускается как `privileged: true` и имеет встроенный тулсет LVM. Он сможет самостоятельно нарезать пул прямо поверх диска `/dev/vdb`, который мы пробросили из Incus.

### `linstor-cluster-values.yaml` (для ArgoCD/Helm)

```yaml
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstor-storage
  namespace: piraeus-datastore
spec:
  controller:
    enabled: true
  satelliteSet:
    storagePools:
      - name: lvm-thin-pool
        lvmThinPool:
          volumeGroup: linstor_vg
          thinPool: thin_pool
          # Указываем оператору автоматически инициализировать пустые диски vdb
          devicePaths:
            - /dev/vdb
```

---

### Архитектурный чек-лист перед запуском `terraform apply`:

1. [ ] Вы создали кастомный образ Talos Linux с расширением `siderolabs/drbd` (9-й ветки).
2. [ ] Вы зафиксировали IP-адрес для Control Plane, чтобы Cilium в конфигурации жестко знал `k8sServiceHost`.
3. [ ] Вы проверили, что подсеть `10.10.10.200/28` для балансировщика Cilium не пересекается с диапазоном выдачи DHCP-сервера Incus.

С какого шага начнем сборку — сгенерируем кастомный образ Talos через Factory API или сразу перейдем к оформлению репозитория для ArgoCD?
