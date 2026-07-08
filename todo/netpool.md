# Сетевая политика (CiliumNetworkPolicy) — диагностика

## Проблема

Gateway (Cilium Gateway API, envoy на hostNetwork) не может подключиться к backends через ClusterIP — таймаут, несмотря на `fromEntities: [host, remote-node, world]` в `argocd.yaml`.

## Что узнали

1. **argocd.yaml** (`endpointSelector: {}`) полностью блокирует gateway upstream — достаточно удалить только его, gateway работает.
2. **kube-system.yaml** (`platform-ingress` с `endpointSelector: {}`) — НЕ блокирует gateway.
3. Cilium (v1.19.4) игнорирует `fromEntities: remote-node` для `argocd/platform-ingress` — в `policy selectors` отображается только `reserved.host`, `world` показывается, `remote-node` — нет.
4. `endpointSelector: {}` vs точечный `endpointSelector` на `argocd-server` — разницы нет, `remote-node` всё равно не применяется.
5. `fromEntities: [world]` тоже не помогает — gateway всё ещё таймаут.

## Тест пройден

- Без `argocd.yaml`: gateway работает
- Без всех CNP (`kubectl delete cnp --all -A`): gateway работает
- C kube-system.yaml + argocd.yaml: не работает
- C kube-system.yaml + argocd.yaml (c `fromEntities: [host, remote-node, world]`): не работает

## Вывод

argocd CNP блокирует upstream от envoy к argocd-server. Причина неясна — даже `fromEntities: [world]` не пропускает трафик с hostNetwork. Возможно:

- Проблема в том как Cilium идентифицирует трафик от hostNetwork envoy через VXLAN туннель
- Нужно исследовать identity назначенный трафику от envoy к ClusterIP
- Возможно проблема в `enable-gateway-api-hostnetwork: false` — envoy слушает только на `127.0.0.1`, upstream идёт через host network stack

## Дальнейшие шаги

- [ ] Включить `gateway-api-hostnetwork-enabled: true` в CiliumConfig (envoy будет слушать на `0.0.0.0`)
- [ ] Или разобраться с identity хоста в VXLAN режиме
- [ ] Или переделать CNP: убрать `endpointSelector: {}`, сделать политики `fromEntities: [world]` для каждого namespace

## Текущий раунд (2026-07-08, после смены NGINX→envoy и hostPort→LoadBalancer)

### Текущее состояние

- Только `kube-system/platform-ingress` в кластере → gateway ОК (HTTP 200)
- Применяем `argocd/platform-ingress` → gateway таймаут (воспроизвели)
- Cilium v1.19.4, `external-envoy-proxy: "true"`, `gateway-api-hostnetwork-enabled: "false"`
- envoy pods: `hostNetwork: true`, IP из LB-пула (10.200.10.x)
- Gateway service: LoadBalancer `cilium-gateway-platform-gateway` → 10.200.10.100
- argocd-server endpoint 1479 (identity 53739) на node talos-m7b-a43 → INGRESS enforcement Enabled

### Аномалия в `cilium-dbg policy selectors`

Для `argocd/platform-ingress` (uid 75eea4df2258) виден только ОДИН selector:
`any.io.kubernetes.pod.namespace: argocd` (5 identities: argocd pods).
Но в YAML ТРИ `fromEndpoints`: argocd, kube-system, monitoring.
Селекторы kube-system и monitoring ОТСУТСТВУЮТ в выводе Cilium.

То же у других политик (per-node кэш на talos-m7b-a43):

- redis: показаны keda, atlasteam-seal, redis — НЕТ monitoring
- vault: показаны external-secrets, vault — НЕТ kube-system/monitoring/remote-node
- minio: показаны minio, database — НЕТ kube-system/velero/monitoring/atlasteam-seal
- velero: показан velero — НЕТ monitoring
- monitoring: вообще не видно селекторов
- kube-system: показаны ВСЕ 4 (kube-system, remote-node, {}, monitoring) ✓

Похоже `policy selectors` показывает неполный набор (per-node дедуп/оптимизация).
НУЖНО проверить напрямую через endpoint policy, а не через selectors.

### План тестов

1. [x] argocd + `fromEntities: [host]` → 503 (не помогло, identity не host)
2. [x] argocd + `fromEntities: [host, remote-node]` → 503 (не помогло)
3. [x] **ROOT CAUSE найден**: `cilium monitor` показал drop с source `10.0.2.244` (cilium_host удалённого node). В ipcache: `10.0.2.244/32 identity=8` = **reserved:ingress** (НЕ host=1, НЕ remote-node=6).
4. [x] argocd + `fromEntities: [ingress]` → **200** ✓ РАБОТАЕТ

### КОРЕНЬ ПРОБЛЕМЫ (ROOT CAUSE)

Cilium Gateway API (envoy external + `gateway-api-hostnetwork-enabled: false`) маркирует весь
трафик, пропущенный через Gateway, identity **`reserved:ingress` (8)**.

Трафик-пат для cross-node upstream:
client → LB 10.200.10.100 → envoy(hostNetwork) на node-A
→ подключение к backend ClusterIP → Cilium DNAT → backend pod на node-B
→ source IP = cilium_host node-A (напр. 10.0.2.244) → туннель → node-B
→ на node-B Cilium в ipcache резолвит 10.0.2.244 → identity=8 (reserved:ingress)

Старые политики (NGINX ingress era) разрешали `fromEndpoints: {namespace: kube-system}`
или `fromEntities: [remote-node]` — НИЧЕГО из этого не матчит `reserved:ingress`.
Поэтому после миграции NGINX→envoy + hostPort→LoadBalancer gateway перестал работать.

kube-system/platform-ingress НЕ блокировал gateway, т.к. он применяется к pod-ам kube-system,
а не к backend-ам (argocd-server и т.д.), у которых не было policy → ingress разрешён по умолчанию.

### РЕШЕНИЕ

Добавить `- fromEntities: [ingress]` в КАЖДУЮ backend-политику, чей сервис доступен через Gateway:

- [x] argocd.yaml (argocd-server) → 200 ✓
- [ ] monitoring.yaml (grafana)
- [ ] vault.yaml (vault)
- [ ] minio.yaml (minio s3 + console)
- [ ] database.yaml (если через gateway)
- [ ] другие backend-политики по мере появления HTTPRoute

### Проверка всех gateway-роутов

HTTPRoutes → backends:

- argocd.atlas, argocd-cli.atlas → argocd-server (argocd) ✓
- grafana.atlas → grafana (monitoring)
- vault.atlas → vault (vault)
- s3.atlas, console.s3.atlas → minio (minio)
- seal.atlas → (HTTPRoute ещё нет, 0 attached)

### РЕЗУЛЬТАТЫ ТЕСТОВ (после добавления `ingress` во все backend-политики)

| Route            | Code | Пояснение                                             |
| ---------------- | ---- | ----------------------------------------------------- |
| argocd.atlas     | 200  | ✓ Gateway→argocd-server:80 работает                   |
| grafana.atlas    | 302  | ✓ редирект на логин (норма)                           |
| vault.atlas      | 307  | ✓ редирект на UI (норма)                              |
| s3.atlas         | 403  | ✓ MinIO отвечает (анинимный доступ запрещён — ок)     |
| console.s3.atlas | 200  | ✓ MinIO console                                       |
| test-ca.atlas    | 200  | ✓ тестовый cert-роут                                  |
| argocd-cli.atlas | 503  | ⚠ НЕ CNP! service argocd-server:443 нет endpoint     |
|                  |      | (targetPort не указан → ищет :443, pod слушает :8083) |
| test-app.atlas   | 000  | ⚠ НЕ CNP! нет listener для hostname test-app.atlas   |
| seal.atlas       | 404  | ✓ нет HTTPRoute (0 attached) — gateway отвечает 404   |

**Вывод:** Все реальные gateway-бэкенды (argocd, grafana, vault, minio) работают
после добавления `fromEntities: [ingress]`. argocd-cli(503) и test-app(000) —
отдельные проблемы конфигурации (service port / gateway listener), НЕ связаны с CNP.

### Изменённые файлы (готовы к коммиту)

- argocd.yaml: + `fromEntities: [ingress]`
- monitoring.yaml: + `fromEntities: [ingress]`
- vault.yaml: + `fromEntities: [ingress]` (к existing remote-node)
- minio.yaml: + `fromEntities: [ingress]`
- database.yaml: + `fromEntities: [ingress]`

Остальные политики (redis, keda, cnpg-system, external-secrets, loki, velero,
nginx-gateway) НЕ трогали — они не являются gateway-бэкендами (трафик pod-to-pod
или внутренний).`
