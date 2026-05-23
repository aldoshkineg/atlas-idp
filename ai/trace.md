Debug the GitHub Actions pipeline failure for **Atlas IDP** (local `kind` cluster + Argo CD).
CRITICAL: Keep log outputs strictly minimal to save context tokens. Never dump full workflow runs. Provide ONLY non-interactive, scriptable commands.

### Tracing & Diagnostic Commands:
* **Silent Wait (CRITICAL for non-TTY):** `gh run watch <run-id> > /dev/null 2>&1` (Blocks until complete. Only rely on its exit code: 0 = success, 1 = fail).
* **Targeted Logs:** `gh run view --log-failed` (Run this ONLY if the silent wait exits with code 1).
* **Current Runner State:** `docker logs github-runner-atlas-idp --tail 20` (Do NOT use `-f` to avoid hanging the agent).
* **Targeted Logs:** `gh run view --log-failed`
* **Artifacts (if needed):** `gh run download <run-id> -n <artifact-name>`

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
