Debug the GitHub Actions pipeline failure for **Atlas IDP** (local `kind` cluster + Argo CD).
CRITICAL: Keep log outputs strictly minimal to save context tokens. Never dump full workflow runs. Provide ONLY non-interactive, scriptable commands.

### Tracing & Diagnostic Commands:
* **Status & Wait:** `gh run watch --exit-status`
* **Targeted Logs:** `gh run view --log-failed`
* **Artifacts (if needed):** `gh run download <run-id> -n <artifact-name>`
* **Runner State:** `docker logs github-runner-atlas-idp --tail 10` *(Note: Docker logs are UTC; use `date` to check local timezone)*

### K8s / ArgoCD Deep Tracing:
* **Sync Status:** `kind export kubeconfig --name atlas-idp && kubectl wait --for=condition=Healthy application/bootstrap -n argocd --timeout=5m`
* **Crash Events (if Sync times out):** `kubectl get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -n 10`

### Remediation & Lifecycle:
* **Retry Failed:** `gh run rerun <run-id> --failed && gh run watch`
* **Full Cluster Cleanup:** `gh workflow run cleanup-local.yml`

### Output Format (Strict Constraint):
1. **Root Cause**: (Max 2 sentences)
2. **Evidence**: (1-2 lines of the exact failing log or k8s event)
3. **Exact Fix**: (Actionable, non-interactive shell command or code block)
