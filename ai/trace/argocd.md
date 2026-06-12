# ArgoCD GitOps Prompt

## Context
- **Login:** `make argocd-login`
- **Repo:** `https://github.com/aldoshkineg/atlas-idp.git` (main)
- **Structure:**
  - `gitops/bootstrap/` — Day-0 (root-app, argocd)
  - `gitops/platform/layers/` — Day-1 Apps (base, networking, security, observability)
  - `gitops/platform/configs/` — Day-1 Configs (gateway, certs)

## Local Loop (Test WITHOUT Git Push)
```bash
argocd app diff <app> --local <dir>  # Dry-run local vs live
argocd app sync <app> --local <dir>  # Apply local direct
helm template <release> ./chart      # Render
kustomize build <dir>                # Render

```

## Quick CLI

```bash
argocd app list | get <app> [--refresh]
argocd app manifests <app> | grep -E "kind:|name:"
argocd app sync <app> --timeout 600
kubectl get/describe <res> <name> -n <ns>

```

## OOM: argocd-repo-server

**Симптом:** `OOMKilled` (Exit 137), рестарты при `helm template` тяжёлых чартов.
**Причина:** 20+ приложений (kube-prometheus-stack, Cilium CRDs, PostgreSQL, KEDA) генерируют манифесты параллельно. Каждый `helm template --include-crds` ест ~300-500 MiB. Default 512Mi не хватает при массовом sync/reconciliation.
**Фикс:** `infra/modules/argocd-bootstrap/main.tf` — repoServer.limits.memory = `2Gi`, requests = `1Gi`.
**Опция:** `ARGOCD_REPO_SERVER_PARALLELISM=3` (ограничить одновременную генерацию).

## Fixes Cheat Sheet

1. **CRD Not Found:** Delay dependent resources via `metadata.annotations: argocd.argoproj.io/sync-wave: "1"`.
2. **ComparisonError (Drift):** Suppress via `spec.ignoreDifferences` (e.g., `jsonPointers: - /status`).
3. **No Namespace:** Add `CreateNamespace=true` to `spec.syncPolicy.syncOptions`.
4. **Helm OCI 404:** Use `repoURL: oci://<registry-url>`.
5. **Race Conditions:** `root-app` must scan ONLY `layers/`. Scan `configs/` via a separate app with `sync-wave: "2"`.

## Workflow

1. Find issue: `argocd app get <app> | grep CONDITION`.
2. Edit YAML in `layers/` or `configs/`.
3. Verify & apply: `argocd app diff/sync <app> --local .`.
4. Commit & push: `git commit -m "fix: ..." && git push`.

## LLM Rules

* **Strict brevity:** Output ONLY changed YAML snippets, NOT full files.
* **Local first:** Suggest `--local` for tests, avoid `git push` in debug loops.
* **Limit output:** Use `| head`, `| grep` in bash commands to save tokens.
