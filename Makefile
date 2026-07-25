# ---------------------------------------------------------------------------
# Atlas IDP — Task dispatcher
#
# The Makefile is intentionally thin: every target delegates to an
# executable wrapper under tools/ (see each section for the script path).
# All real logic lives in those scripts so the Makefile stays declarative
# and easy to audit.
#
# Help is self-documenting: a `##` after a target documents it, `##@` starts a
# group. Run `make` (or `make help`) to print it.
# ---------------------------------------------------------------------------

.DEFAULT_GOAL := help

# Auto-load .env if present (local B2 credentials, Vault seeds, etc.)
-include .env
export

# --- Shared locations ------------------------------------------------------
TF_PLUGIN_CACHE_DIR ?= /var/tmp/atlas/act_cache/tf

LOCAL_RUNNER_DIR ?= tools/ci/local-runner
ACT_RUNNER_DIR   ?= tools/ci/act-runner

ATLASCTL_BIN ?= tools/atlasctl/bin/atlasctl

# Taskfiles (invoked via go-task)
SEAL_TASKFILE     ?= apps/seal/Taskfile.yml
ATLASCTL_TASKFILE ?= tools/atlasctl/Taskfile.yml

INCUS_SNAP_SCRIPT ?= tools/incus/incus-control.sh

# Snapshot name for incus-snap-* targets, e.g. make incus-snap-restore SNAP=my-snap
SNAP ?=

# App/group argument for atlasctl targets, e.g. make atlasctl-status ARGS=aldoshkineg/seal
ARGS ?=

# --- Phony targets ---------------------------------------------------------
.PHONY: help \
	stage-sync \
	ci-runner-up ci-runner-down ci-runner-logs \
	ci-runner-apply ci-runner-ci ci-runner-base ci-runner-middle ci-runner-workload \
	ci-runner-destroy ci-runner-destroy-force \
	act-build act-ci act-stage-base act-stage-middleware act-stage-workload act-destroy act-destroy-force \
	argocd-login \
	seed-vault seed-gh \
	atlasctl-build atlasctl-test atlasctl-vet atlasctl-new atlas-seal atlasctl-list atlasctl-status \
	seal-build seal-push seal-dc-up seal-dc-down seal-dc-logs seal-unit \
	rbac-apply rbac-delete \
	test test-ca-gateway test-vault test-velero test-keda test-redis \
	test-network-policy test-db-backup test-seal test-argocd-rollout test-undeploy \
	validate validate-terraform validate-yaml validate-security pre-commit \
	preflight \
	seal-verify \
	incus-snap-create incus-snap-restore incus-snap-list incus-snap-delete \
	incus-vm-stop incus-vm-start

# --- Help (self-documenting) ----------------------------------------------
help:
	@echo "Atlas IDP (Internal Developer Platform)"
	@echo "Quick start:  make preflight  →  make act-stage-base"
	@echo "Full guide:   docs/setup.md"
	@echo
	@awk 'BEGIN{ if (system("test -t 1") == 0) { c="\033[0m"; h="\033[1;36m"; d="\033[2m" } else { c=h=d="" } } \
	  /^##@/ { sub(/^##@ ?/,""); printf "\n%s%s:%s\n", h, $$0, c; next } \
	  /^[a-zA-Z0-9_%/-]+[[:space:]]*:[^=].*## / { \
	    t = $$0; sub(/:.*/, "", t); \
	    d2 = $$0; sub(/.*## /, "", d2); \
	    printf "  %-28s %s%s%s\n", t, d, d2, c }' $(MAKEFILE_LIST)

##@ Getting Started
preflight: ## Verify host readiness (binaries, daemons, .env, images) [run before any pipeline]
	./tools/ci/preflight.sh

##@ Local Run (act)
act-ci: ## Run full CI pipeline (base+middleware+workload) via act
	$(ACT_RUNNER_DIR)/act-runner.sh ci

act-stage-base: ## Run base stage (infra + vault seeds) via act
	$(ACT_RUNNER_DIR)/act-runner.sh base

act-stage-middleware: ## Sync platform layers (DB/MinIO/monitoring) via act
	$(ACT_RUNNER_DIR)/act-runner.sh middleware

act-stage-workload: ## Sync workloads (seal) + seed workloads via act
	$(ACT_RUNNER_DIR)/act-runner.sh workload

act-destroy: ## Destroy stage infrastructure via act (ci-destroy workflow)
	$(ACT_RUNNER_DIR)/act-runner.sh destroy

act-destroy-force: ## Hard teardown of stage (Incus/Talos + TF state) via ci-destroy-force workflow
	$(ACT_RUNNER_DIR)/act-runner.sh destroy-force

act-build: ## Build custom act runner image
	$(ACT_RUNNER_DIR)/act-runner.sh build

##@ Runner (self-hosted)
ci-runner-up: ## Start self-hosted GitHub runner (needs Docker+Incus)
	./$(LOCAL_RUNNER_DIR)/runner.sh up

ci-runner-down: ## Stop and remove the runner container
	./$(LOCAL_RUNNER_DIR)/runner.sh down

ci-runner-logs: ## Follow runner logs
	./$(LOCAL_RUNNER_DIR)/runner.sh logs

ci-runner-apply: ## Dispatch apply via runner (ci-base workflow)
	./$(LOCAL_RUNNER_DIR)/runner.sh apply

ci-runner-ci: ## Dispatch full CI via runner (ci-all workflow)
	./$(LOCAL_RUNNER_DIR)/runner.sh ci

ci-runner-base: ## Dispatch base stage via runner
	./$(LOCAL_RUNNER_DIR)/runner.sh base

ci-runner-middle: ## Dispatch middleware stage via runner
	./$(LOCAL_RUNNER_DIR)/runner.sh middleware

ci-runner-workload: ## Dispatch workload stage via runner
	./$(LOCAL_RUNNER_DIR)/runner.sh workload

ci-runner-destroy: ## Dispatch destroy via runner (ci-destroy workflow)
	./$(LOCAL_RUNNER_DIR)/runner.sh destroy

ci-runner-destroy-force: ## Dispatch hard teardown via runner
	./$(LOCAL_RUNNER_DIR)/runner.sh destroy-force

##@ GitOps
stage-sync: ## Sync GitOps platform layers
	./tools/ci/sync-layers.sh

argocd-login: ## Login to ArgoCD via CLI
	./tools/argocd-login.sh

argolist: ## List ArgoCD apps by layer [base|security|storage|delivery|observability|workloads|all]
	./tools/argocd-list.sh $(filter-out $@,$(MAKECMDGOALS))

# Layer words accepted as positional args for `argolist` (e.g. `make argolist base`).
# Declared as no-op phony targets so Make does not treat them as real goals.
.PHONY: base security storage delivery observability workloads all
base security storage delivery observability workloads all:
	@:

##@ Vault & Secrets
seed-vault: ## Read .env + seed-mapping.conf, seed into Vault via port-forward
	@unset VAULT_ADDR; ./security/vault/seed-vault.sh

seed-gh: ## Upload the whole .env as one GitHub Secret (ENV_FILE)
	./security/vault/seed-gh.sh

##@ Workloads (atlasctl)
atlasctl-build: ## Build the atlasctl Go binary
	go-task -t $(ATLASCTL_TASKFILE) build

atlasctl-test: ## Run atlasctl unit tests
	go-task -t $(ATLASCTL_TASKFILE) test

atlasctl-vet: ## Run 'go vet' on atlasctl
	go-task -t $(ATLASCTL_TASKFILE) vet

atlasctl-new: ## Scaffold a new workload (see: $(ATLASCTL_BIN) new --help)
	@echo "Scaffold a new workload:"
	@echo "  $(ATLASCTL_BIN) new <app> --group <group> --repo <url> [options]"
	@echo "Example:"
	@echo "  $(ATLASCTL_BIN) new seal --group aldoshkineg --repo https://github.com/aldoshkineg/atlas-idp.git --repo-path charts/seal --helm"
	@echo "Build first: make atlasctl-build"

atlas-seal: ## Seed Seal workload secrets into Vault [ARGS=group/app]
	$(ATLASCTL_BIN) seed $(ARGS)

atlasctl-list: ## List all registered workloads
	$(ATLASCTL_BIN) list

atlasctl-status: ## Show status of a workload [ARGS=group/app]
	$(ATLASCTL_BIN) status $(ARGS)

##@ Apps (seal)
seal-build: ## Build all seal Docker images (api/worker/ui)
	go-task -t $(SEAL_TASKFILE) build-all

seal-push: ## Tag + push seal images to GHCR (needs .env) [TAG=<git tag or empty>]
	go-task -t $(SEAL_TASKFILE) push-images

seal-dc-up: ## Start seal integration stack (docker compose)
	go-task -t $(SEAL_TASKFILE) dc-up

seal-dc-down: ## Stop seal integration stack
	go-task -t $(SEAL_TASKFILE) dc-down

seal-dc-logs: ## Follow seal integration stack logs
	go-task -t $(SEAL_TASKFILE) dc-logs

seal-unit: ## Run seal Go unit tests
	go-task -t $(SEAL_TASKFILE) test

##@ Tests
TESTS := test-ca-gateway test-vault test-network-policy test-velero test-keda test-redis test-db-backup test-argocd-rollout test-seal
test: $(TESTS) ## Deploy and verify all platform tests

test-ca-gateway: ## Deploy CA gateway test and verify TLS endpoint
	./tests/scripts/gateway-test.sh

test-vault: ## Seed Vault, deploy injection pod, verify secrets
	./tests/scripts/vault-test.sh

test-velero: ## Test Velero backup/restore to S3
	./tests/scripts/velero-test.sh

test-keda: ## Test KEDA autoscaling via ConfigMap trigger
	./tests/scripts/keda-test.sh

test-redis: ## Test Redis availability/connectivity
	./tests/scripts/redis-test.sh

test-network-policy: ## Test NetworkPolicy isolation between pods
	./tests/scripts/network-policy-test.sh

test-db-backup: ## Test CNPG backup/restore to MinIO
	./tests/scripts/db-backup-test.sh

test-seal: ## Test Seal deployment (pods, API, documents, gateway)
	./tests/scripts/seal-test.sh

test-argocd-rollout: ## Test Argo Rollouts canary progression
	./tests/scripts/argocd-rollout-test.sh

test-undeploy: ## Remove all test resources
	./tests/scripts/test-undeploy.sh

##@ Quality
validate: validate-terraform validate-yaml validate-security ## Run fmt/validate checks (Terraform, Yamllint, Trivy)

validate-terraform: ## Terraform fmt/validate
	./tools/ci/validate.sh terraform

validate-yaml: ## YAML lint
	./tools/ci/validate.sh yaml

validate-security: ## Security scan (Trivy)
	./tools/ci/validate.sh security

pre-commit: ## Run pre-commit hooks on all project files
	./tools/ci/pre-commit.sh

##@ Security & RBAC
rbac-apply: ## Apply RBAC policies (ClusterRoles, bindings)
	./tools/rbac/rbac.sh apply

rbac-delete: ## Remove RBAC policies
	./tools/rbac/rbac.sh delete

seal-verify: ## Verify Seal image signatures (cosign) [TAG=vX.Y.Z]
	./tools/security/seal-verify.sh $(TAG)

##@ Incus VM lifecycle
incus-snap-create: ## Snapshot all Talos VMs [SNAP=name]
	$(INCUS_SNAP_SCRIPT) create $(SNAP)

incus-snap-restore: ## Restore all Talos VMs from a snapshot [SNAP=name]
	@test -n "$(SNAP)" || (echo "Usage: make incus-snap-restore SNAP=<name>" >&2; exit 1)
	$(INCUS_SNAP_SCRIPT) restore $(SNAP)

incus-snap-list: ## List snapshots for all Talos VMs
	$(INCUS_SNAP_SCRIPT) list

incus-snap-delete: ## Delete a named snapshot [SNAP=name]
	@test -n "$(SNAP)" || (echo "Usage: make incus-snap-delete SNAP=<name>" >&2; exit 1)
	$(INCUS_SNAP_SCRIPT) delete $(SNAP)

incus-vm-stop: ## Stop Talos VM(s) [VM=name|all]
	$(INCUS_SNAP_SCRIPT) stop $(or $(VM),all)

incus-vm-start: ## Start Talos VM(s) [VM=name|all]
	$(INCUS_SNAP_SCRIPT) start $(or $(VM),all)
