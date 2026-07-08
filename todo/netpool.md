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
