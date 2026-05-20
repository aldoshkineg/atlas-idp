# GitHub Actions Runner (Self-Hosted)

Self-hosted GitHub Actions runner running in Docker. Part of the atlas-idp CI/CD infrastructure.

## Security Notes

⚠️ **Never commit tokens or `.env` file to version control**

- Runner tokens are short-lived registration tokens
- Use `.env.example` as template and create your own `.env`
- The `.env` file is gitignored

## Quick Start

1. **Get a registration token** (requires GitHub PAT):
   ```bash
   ./setup-runner.sh <your-github-pat>
   ```

2. **Set the token and start the runner**:
   ```bash
   export RUNNER_TOKEN=<token-from-step-1>
   make start
   # OR with docker-compose directly:
   RUNNER_TOKEN=<token> docker-compose up -d
   ```

3. **Using .env file** (recommended):
   ```bash
   cp .env.example .env
   # Edit .env and add your RUNNER_TOKEN
   docker-compose up -d
   ```

## Make Commands

- `make setup` - Show setup instructions
- `make start` - Start the runner (requires RUNNER_TOKEN)
- `make stop` - Stop the runner
- `make restart` - Restart the runner
- `make status` - Check runner status
- `make logs` - View runner logs
- `make remove` - Remove the runner container

## Managing Runners

Remove runner from GitHub:
https://github.com/aldoshkineg/atlas-idp/settings/actions/runners
