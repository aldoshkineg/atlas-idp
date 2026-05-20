.PHONY: help cluster-up cluster-down infra-init infra-plan gitops-bootstrap validate pre-commit \
	secrets-init runner-up runner-register runner-down runner-logs runner-create-api

CLUSTER_NAME ?= atlas-idp
KIND_CONFIG  ?= clusters/kind/cluster.yaml
CI_CLUSTER   ?= atlas-idp-ci
ENV          ?= local-kind
RUNNER_DIR   ?= infra/environments/local-kind/gitlab-runner

help:
	@echo "Targets:"
	@echo "  cluster-up        Create kind cluster"
	@echo "  cluster-down      Delete kind cluster"
	@echo "  infra-init        Terraform init (ENV=$(ENV))"
	@echo "  infra-plan        Terraform plan (ENV=$(ENV))"
	@echo "  gitops-bootstrap  Install Argo CD (day-0) and apply root app"
	@echo "  validate          Run fmt/validate checks"
	@echo "  pre-commit        Run pre-commit on all files"
	@echo "  secrets-init      Copy $(RUNNER_DIR)/.env.example → .env"
	@echo "  runner-create-api Create runner via GitLab API (GITLAB_PAT in .env)"
	@echo "  runner-register   Register GitLab Runner ($(RUNNER_DIR)/)"
	@echo "  runner-up         Register + start GitLab Runner container"
	@echo "  runner-down       Stop GitLab Runner container"
	@echo "  runner-logs       Follow GitLab Runner logs"

cluster-up:
	./clusters/scripts/create-cluster.sh

cluster-down:
	./clusters/scripts/destroy-cluster.sh

cluster-ci-up:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-provision.sh

cluster-ci-down:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-down.sh

infra-init:
	cd infra/environments/$(ENV) && terraform init

infra-plan:
	cd infra/environments/$(ENV) && terraform plan

gitops-bootstrap:
	./clusters/scripts/bootstrap-gitops.sh

validate:
	terraform fmt -check -recursive infra/
	@command -v trivy >/dev/null && trivy config --severity HIGH,CRITICAL infra/ gitops/ || echo "trivy not installed, skip"
	@command -v yamllint >/dev/null && yamllint -c .yamllint.yml gitops/ observability/ security/ || echo "yamllint not installed, skip"

pre-commit:
	pre-commit run --all-files

secrets-init:
	@if [ -f $(RUNNER_DIR)/.env ]; then \
		echo "Already exists: $(RUNNER_DIR)/.env"; \
	else \
		cp $(RUNNER_DIR)/.env.example $(RUNNER_DIR)/.env; \
		chmod 600 $(RUNNER_DIR)/.env; \
		echo "Created $(RUNNER_DIR)/.env — edit and add tokens"; \
	fi

runner-create-api:
	./$(RUNNER_DIR)/create-runner-via-api.sh

runner-register:
	./$(RUNNER_DIR)/register.sh

runner-up:
	./$(RUNNER_DIR)/start.sh

runner-down:
	docker compose -f $(RUNNER_DIR)/docker-compose.yml down

runner-logs:
	docker compose -f $(RUNNER_DIR)/docker-compose.yml logs -f
