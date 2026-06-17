.PHONY: setup stop restart status logs remove

setup:
	@echo "Setting up GitHub Actions Runner..."
	@chmod +x setup-runner.sh
	@./setup-runner.sh

stop:
	docker compose stop

restart:
	docker compose restart

status:
	docker compose ps

logs:
	docker compose logs -f

remove:
	docker compose down -v
	@echo "--------------------------------------------------------"
	@echo "Runner container and Docker volumes stopped and removed locally."
	@echo "Remember to clean it up from your GitHub repository if needed:"
	@echo "https://github.com/aldoshkineg/atlas-idp/settings/actions/runners"
	@echo "--------------------------------------------------------"
