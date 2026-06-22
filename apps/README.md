# Apps / Workloads

Каждое приложение команды живёт по схеме `workloads/<group>/<app>/` со своей инфраструктурой (Vault, БД, S3, мониторинг).

## Golden Path — создание нового workload

```bash
tools/atlasctl new <app> --group <group> --repo <url> [options]
```

Обязательные параметры:

- `--group <group>` — команда разработки (e.g., `aldoshkineg`, `devteam`)
- `--repo <url>` — URL репозитория приложения

Опции:

- `--namespace <ns>` — Kubernetes namespace (по умолчанию `<group>-<app>`)
- `--repo-path <p>` — путь до Helm/k8s манифестов в репозитории (по умолчанию `.`)
- `--helm` — использовать Helm-чарт
- `--helm-values <s>` — inline значения Helm или путь к файлу
- `--secrets` — Vault policy + K8s auth role + seed-mapping
- `--db` — выделенный CNPG кластер БД
- `--s3` — MinIO S3 bucket + ExternalSecret
- `--monitoring` — PodMonitor + PrometheusRule

Схема директорий после создания:

```
workloads/<group>/
  <app>/
    app.yaml              # ArgoCD Application → внешний репозиторий
    infra.yaml            # ArgoCD Application → внутренняя инфраструктура
    vault/                # Vault policy, K8s auth role, seed-mapping
    database/             # CNPG Cluster, backup, ExternalSecrets
    s3/                   # MinIO ExternalSecrets
    monitoring/           # PodMonitor, PrometheusRule

gitops/workloads/layers/<group>/
  <app>.yaml              # ArgoCD Application CR (→ workloads/<group>/<app>/app.yaml)
  <app>-infra.yaml        # ArgoCD Application CR (→ workloads/<group>/<app>/)
```

## Seal

Проект Seal (подпись PDF) живёт в [aldoshkineg/atlas-idp-seal](https://github.com/aldoshkineg/atlas-idp-seal).

ArgoCD Application: `gitops/workloads/layers/aldoshkineg/seal.yaml`

Инфраструктура Seal (Vault, БД, S3, мониторинг): `workloads/aldoshkineg/seal/`
