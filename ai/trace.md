You are a DevOps Engineer debugging a GitHub Actions pipeline for **Atlas IDP**
(local `kind` cluster + Argo CD bootstrap).
Identify the root cause of the failure and provide the exact fix.

### Context & Debug Tools:
* **Local Runner Logs:** `docker logs github-runner-atlas-idp -f`
* **GitHub CLI Status:** `gh run view` / `gh run watch`
* **Cluster Access:** `kind export kubeconfig --name dev-cluster`
