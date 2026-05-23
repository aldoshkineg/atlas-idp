.PHONY: setup start stop restart status logs remove

setup:
	@echo "Setting up GitHub Actions Runner..."
	@echo "Please run: ./setup-runner.sh <your-github-pat>"

start:
	@if [ -z "$(RUNNER_TOKEN)" ] && [ -z "$$RUNNER_TOKEN" ]; then \
		echo "Error: RUNNER_TOKEN not set"; \
		echo "Get a token with: ./setup-runner.sh <your-github-pat>"; \
		echo "Or use: RUNNER_TOKEN=<token> make start"; \
		exit 1; \
	fi
	docker compose up -d

stop:
	docker compose stop

restart:
	docker compose restart

status:
	docker compose ps

logs:
	docker compose logs -f

remove:
	docker compose down
	@echo "Runner removed. You may also want to remove it from GitHub:"
	@echo "https://github.com/aldoshkineg/atlas-idp/settings/actions/runners"
