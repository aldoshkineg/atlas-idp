# GitLab Runner (local-kind)

Part of the **local-kind** environment. Runs on the host Docker and executes CI jobs (including kind cluster provisioning).

Sensitive files (gitignored):

- `.env` — `cp .env.example .env`
- `config/` — created by `register.sh`

From repository root:

```bash
make secrets-init
make runner-up
```
