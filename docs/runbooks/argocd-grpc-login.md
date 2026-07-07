# ArgoCD gRPC Login через Gateway

## Описание проблемы

argocd CLI не может залогиниться через Cilium Gateway API на порт 443.

## Архитектура трафика

```
Client (argocd CLI)
  │
  │  TLS (ALPN h2) ─── порт 443
  ▼
Cilium Gateway (Envoy)
  │
  │  TLS termination → HTTP/2 gRPC
  │  Cilium BPF обрабатывает gRPC минуя envoy
  ▼
argocd-server:8080 (HTTP/1.1, Go net/http)
```

```
Client (Web UI / curl --http1.1)
  │
  │  TLS (ALPN http/1.1) ─── порт 443
  ▼
Cilium Gateway (BPF direct path)
  │
  │  REST API (HTTP/1.1)
  ▼
argocd-server:8080
```

## Рабочее решение

| Компонент        | Значение                                                                                              |
| ---------------- | ----------------------------------------------------------------------------------------------------- |
| Gateway listener | HTTPS, порт 443 (TLS terminate)                                                                       |
| HTTPRoute        | `sectionName: https-argocd`, `backendRef port: 443`                                                   |
| Service          | без `appProtocol` (HTTP/1.1 upstream)                                                                 |
| Cilium ConfigMap | `enable-gateway-api-alpn: true`                                                                       |
| Cilium ConfigMap | `enable-gateway-api-app-protocol: false` (default)                                                    |
| upstream cluster | `http/1.1` (Cilium BPF обрабатывает напрямую)                                                         |
| argocd login     | `--username admin --password ...` (без `--grpc-web`, без `--insecure`)                                |
| Envoy image      | `v1.36.6-1778235340-b87d1e32f522b33bd51701c6476d199326f01496` (hash должен совпадать с Cilium daemon) |

## Требования к конфигурации

### infra/environments/stage/main.tf (Cilium)

```hcl
cilium_settings = [
  { name = "hubble.enabled", value = "true", type = "auto" },
  { name = "gatewayAPI.enabled", value = "true", type = "auto" },
  { name = "gatewayAPI.enableAlpn", value = "true", type = "auto" },
  ...
]
```

### gitops/.../gateway-routes/argocd.yaml

```yaml
parentRefs:
  - name: platform-gateway
    namespace: kube-system
    sectionName: https-argocd
hostnames:
  - argocd.atlas
rules:
  - backendRefs:
      - name: argocd-server
        port: 443 # не 80!
```

### tools/argocd-login.sh

Использует `expect` + нативный gRPC (без `--grpc-web`, без `--insecure`).

## Что не работает

- **h2c** (`appProtocol: kubernetes.io/h2c`) — argo-cd v2.13.1 не поддерживает h2c на порту 8080. Envoy пытается соединиться через HTTP/2, upstream сбрасывает соединение.
- **gRPC-web** (`--grpc-web`) — Cilium добавляет `grpc_web` filter в Envoy, который конвертирует gRPC-web → нативный gRPC (HTTP/2). upstream HTTP/1.1 не принимает.
- **route порт 80** — не было ALPN-проблемы на старом кластере, но на новом после пересборки возвращает 404.
- **Кастомные ports** (`server.service.ports`) — chart v7.7.5 не поддерживает `appProtocol` через кастомные ports.

## История изменений

| Коммит    | Изменения                                                                      |
| --------- | ------------------------------------------------------------------------------ |
| `e231476` | ALPN (`gatewayAPI.alpn.enabled`) + `appProtocol: h2c` кастомные ports          |
| `c258e66` | ALPN → `gatewayAPI.enableAlpn` + `servicePortHttpsAppProtocol: h2c`, route 443 |
| `757a48c` | route 443 → 80 (h2c не работает с argo-cd), gRPC-web через HTTP/1.1            |
| `2eeeef1` | **откат**: убрал ALPN + servicePortHttpsAppProtocol                            |
| `fa8bfd7` | ALPN (`gatewayAPI.enableAlpn = true`)                                          |
| `2437a4f` | h2c (`servicePortHttpsAppProtocol = "kubernetes.io/h2c"`) + route 443          |
| `59d7345` | убрал h2c, ALPN + HTTP/1.1 upstream                                            |

## Текущий статус (2026-07-08)

**Решение найдено, работает.**

Настройки:

- `gatewayAPI.enableAlpn = true` (включён ALPN h2,http/1.1)
- Route port 443 (HTTPS listener)
- Service без appProtocol (HTTP/1.1 upstream)
- Envoy image tag: `v1.36.6-1778235340-b87d1e32f522b33bd51701c6476d199326f01496`

Логика:

- **gRPC** (argocd CLI): TLS с ALPN h2 → Cilium BPF обрабатывает напрямую (минуя envoy) → upstream argocd-server:8080
- **REST** (Web UI): TLS с ALPN http/1.1 → Cilium BPF direct path → upstream argocd-server:8080

**Важно:** при пересоздании кластера на новом нужно удалить CEC и перезапустить cilium-operator, иначе gRPC может не работать:

```bash
kubectl delete CiliumEnvoyConfig -n kube-system cilium-gateway-platform-gateway
kubectl rollout restart -n kube-system deployment cilium-operator
```

Также требуется правильный тег envoy image в `infra/modules/cilium/variables.tf` (должен совпадать с хэшем Cilium daemon).
