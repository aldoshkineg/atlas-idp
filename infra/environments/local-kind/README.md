# local-kind environment

Local platform stack on this machine:

| Component | Path |
|-----------|------|
| Terraform (cluster metadata, Argo day-0) | `.` (`main.tf`) |
| kind cluster scripts | `../../../clusters/` |
| GitLab Runner (Docker) | `gitlab-runner/` |

## GitLab Runner

```bash
make secrets-init    # from repo root
make runner-up       # register + start container
```

Secrets: `gitlab-runner/.env` and `gitlab-runner/config/` (gitignored).

## CI (kind smoke test)

`ci/kind.yml`: `kind:create` → `kind:verify` → `kind:delete` (always).

Runner tags: `atlas-idp`, `kind`, `local`.
