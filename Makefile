.PHONY: help cluster-up cluster-down cluster-ci-up cluster-ci-down \
	infra-init infra-plan gitops-bootstrap validate pre-commit \
	ci-cache-up ci-cache-purge ci-runner-up ci-runner-down ci-runner-status ci-runner-logs

CLUSTER_NAME     ?= atlas-idp
KIND_CONFIG      ?= clusters/kind/cluster.yaml
CI_CLUSTER       ?= atlas-idp-ci
ENV              ?= local-kind

# Local CI / Automation Directories
LOCAL_RUNNER_DIR ?= clusters/kind/ci/local-runner
ZOT_DIR          ?= clusters/kind/ci/zot-kind-cache

help:
	@echo "Available Targets:"
	@echo "  cluster-up        Create main kind cluster"
	@echo "  cluster-down      Delete main kind cluster"
	@echo "  cluster-ci-up     Provision local CI-specific kind cluster"
	@echo "  cluster-ci-down   Tear down local CI-specific kind cluster"
	@echo "  infra-init        Terraform init (ENV=$(ENV))"
	@echo "  infra-plan        Terraform plan (ENV=$(ENV))"
	@echo "  gitops-bootstrap  Install Argo CD (day-0) and apply root app"
	@echo "  validate          Run fmt/validate checks (Terraform, Trivy, Yamllint)"
	@echo "  pre-commit        Run pre-commit hooks on all project files"
	@echo ""
	@echo "Local CI & Registry Cache Subsystem:"
	@echo "  ci-cache-up       Deploy/verify Zot local registry proxy cache"
	@echo "  ci-cache-purge    Wipe the Zot container registry completely"
	@echo "  ci-runner-up      Fetch fresh token via 'gh' and start local GitHub runner"
	@echo "  ci-runner-down    Stop and remove local GitHub runner container"
	@echo "  ci-runner-status  Check status of local GitHub runner container"
	@echo "  ci-runner-logs    Follow logs from the local GitHub runner container"

# --- Infrastructure Management ---
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

# --- Quality Assurance & Linting ---
validate:
	terraform fmt -check -recursive infra/
	@command -v trivy >/dev/null && trivy config --severity HIGH,CRITICAL infra/ gitops/ || echo "trivy not installed, skip"
	@command -v yamllint >/dev/null && yamllint -c .yamllint.yml gitops/ observability/ security/ || echo "yamllint not installed, skip"

pre-commit:
	pre-commit run --all-files

# --- Local CI & Registry Cache Subsystem ---

ci-cache-up:
	@chmod +x $(ZOT_DIR)/setup-zot-cache.sh
	cd $(ZOT_DIR) && ./setup-zot-cache.sh

ci-cache-purge:
	@chmod +x $(ZOT_DIR)/setup-zot-cache.sh
	cd $(ZOT_DIR) && ./setup-zot-cache.sh --purge

ci-runner-up:
	@chmod +x $(LOCAL_RUNNER_DIR)/setup-runner.sh
	cd $(LOCAL_RUNNER_DIR) && ./setup-runner.sh

ci-runner-down:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml down

ci-runner-status:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml ps

ci-runner-logs:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml logs -f
