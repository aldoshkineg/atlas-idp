# ArgoCD gRPC Login через Gateway

## Описание проблемы

argocd CLI (gRPC) и Web UI (REST) не могут одновременно работать через один Gateway listener из-за конфликта протоколов upstream:

- gRPC требует HTTP/2 (h2c) upstream
- Web UI требует HTTP/1.1 upstream
- ArgoCD в режиме `--insecure` не является полноценным h2c сервером для всех типов запросов

**Решение:** два hostname — `argocd.atlas` (Web UI, HTTP/1.1) и `argocd-cli.atlas` (CLI, h2c).

## Архитектура трафика

### Web UI (argocd.atlas)

```
Browser
  │  TLS (ALPN http/1.1) → порт 443
  ▼
Cilium Gateway (listener https-argocd)
  │  TLS termination → HTTP/1.1 REST
  ▼
argocd-server:8080 (port 80, HTTP/1.1 upstream)
```

### CLI (argocd-cli.atlas)

```
argocd CLI
  │  TLS (ALPN h2) → порт 443
  ▼
Cilium Gateway (listener https-argocd-cli)
  │  TLS termination → HTTP/2 gRPC → h2c upstream
  ▼
argocd-server:8080 (port 443, h2c upstream)
```

## Финальное решение

| Компонент                 | argocd.atlas (Web UI) | argocd-cli.atlas (CLI) |
| ------------------------- | --------------------- | ---------------------- |
| Gateway listener          | `https-argocd`        | `https-argocd-cli`     |
| HTTPRoute sectionName     | `https-argocd`        | `https-argocd-cli`     |
| HTTPRoute backendRef port | 80                    | 443                    |
| Service appProtocol       | нет (HTTP/1.1)        | `kubernetes.io/h2c`    |
| upstream cluster          | `httpProtocolOptions` | `http2ProtocolOptions` |
| ALPN                      | `h2,http/1.1`         | `h2,http/1.1`          |
| argocd login              | не используется       | `argocd-cli.atlas`     |

## Требования к конфигурации

### infra/environments/stage/main.tf (Cilium)

```hcl
cilium_settings = [
  { name = "gatewayAPI.enabled", value = "true", type = "auto" },
  { name = "gatewayAPI.enableAlpn", value = "true", type = "auto" },
  ...
]
```

### infra/modules/argocd-bootstrap/main.tf

```hcl
server = {
  service = {
    type                        = "ClusterIP"
    servicePortHttpsAppProtocol = "kubernetes.io/h2c"
  }
}
```

### gitops/.../gateway-resources/gateway.yaml

Два listener'а:

```yaml
- name: https-argocd
  hostname: "argocd.atlas"
  certificateRefs: [{ name: argocd-cert }]
- name: https-argocd-cli
  hostname: "argocd-cli.atlas"
  certificateRefs: [{ name: argocd-cli-cert }]
```

### gitops/.../gateway-routes/argocd.yaml (Web UI)

```yaml
hostnames: [argocd.atlas]
rules:
  - backendRefs:
      - name: argocd-server
        port: 80
```

### gitops/.../gateway-routes/argocd-cli.yaml (CLI)

```yaml
hostnames: [argocd-cli.atlas]
rules:
  - backendRefs:
      - name: argocd-server
        port: 443
```

### tools/argocd-login.sh

```bash
ARGOCD_SERVER="argocd-cli.atlas"
expect -c "
    spawn argocd login \$ARGOCD_SERVER --username admin --password ...
    expect { \"logged in successfully\" { exit 0 } }
"
```

### infra/modules/cilium/variables.tf

```hcl
variable "envoy_image_tag" {
  default = "v1.36.6-1778235340-b87d1e32f522b33bd51701c6476d199326f01496"
}
```

## DNS

Оба hostname должны резолвиться в LB IP (10.200.10.100):

- `argocd.atlas` → 10.200.10.100
- `argocd-cli.atlas` → 10.200.10.100

## Ключевые инсайты

1. ArgoCD `--insecure` не является полноценным h2c сервером — gRPC (h2c) работает, обычный HTTP/2 GET — нет
2. `enable-gateway-api-alpn` включает ALPN на listener (downstream), достаточно для h2c upstream при `appProtocol: kubernetes.io/h2c`
3. Cilium автоматически определяет upstream протокол по `appProtocol` на сервисе — без `enable-gateway-api-app-protocol`
4. Envoy image tag должен совпадать с хэшем Cilium daemon (проверка версии при старте)

## Что не работает (одним listener'ом)

- **h2c на одном listener** — Web UI ломается (415/503 curl)
- **HTTP/1.1 на одном listener** — gRPC ломается (404)
- **gRPC-web** (`--grpc-web`) — Cilium `grpc_web` filter конвертирует в нативный gRPC (HTTP/2), upstream не принимает
- **route порт 80 без h2c** — gRPC не работает
- **Кастомные ports** — chart v7.7.5 не поддерживает `appProtocol` через кастомные ports

## История изменений

| Коммит    | Изменения                                                                               |
| --------- | --------------------------------------------------------------------------------------- |
| `e231476` | ALPN + `appProtocol: h2c` кастомные ports                                               |
| `c258e66` | ALPN → `gatewayAPI.enableAlpn` + `servicePortHttpsAppProtocol: h2c`, route 443          |
| `757a48c` | route 443 → 80, gRPC-web через HTTP/1.1                                                 |
| `2eeeef1` | откат ALPN + h2c                                                                        |
| `fa8bfd7` | ALPN                                                                                    |
| `2437a4f` | h2c + route 443                                                                         |
| `59d7345` | убрал h2c, ALPN + HTTP/1.1                                                              |
| `019cef1` | **финал**: два hostname — argocd.atlas (Web UI, HTTP/1.1) + argocd-cli.atlas (CLI, h2c) |
