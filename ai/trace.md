Debug the GitHub Actions pipeline failure for **Atlas IDP** (local `kind` cluster + Argo CD).
CRITICAL: Keep log outputs strictly minimal to save context tokens. Never dump full workflow runs.

### Action & Diagnostic Commands:
* **Status & Wait:** `gh run watch --exit-status`
* **Targeted Logs:** `gh run view --log-failed` (Always use this instead of full logs)
* **Local Runner:** `docker logs github-runner-atlas-idp --tail 10`
* **ArgoCD Sync:** `kind export kubeconfig --name atlas-idp && kubectl wait --for=condition=Healthy application/bootstrap -n argocd --timeout=5m`

### Remediation & Lifecycle Commands:
* **Retry Failed:** `gh run rerun <run-id> --failed && gh run watch`
* **Full Cluster Cleanup:** Trigger via `gh workflow run cleanup-local.yml`, track via `gh run list --workflow="cleanup-local.yml"`

### Output Format (Strict Constraint):
1. **Root Cause**: (Max 2 sentences)
2. **Evidence**: (1-2 lines of the exact failing log)
3. **Exact Fix**: (Actionable code/command block)
