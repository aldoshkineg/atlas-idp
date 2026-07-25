# ---------------------------------------------------------------------------
# Atlas IDP — Task dispatcher
#
# The Makefile is intentionally thin: every target delegates to an
# executable wrapper under tools/ (see each section for the script path).
# All real logic lives in those scripts so the Makefile stays declarative
# and easy to audit.
# ---------------------------------------------------------------------------

ENV ?= stage

# Auto-load .env if present (local B2 credentials, Vault seeds, etc.)
-include .env
export

# --- Shared locations ------------------------------------------------------
TF_PLUGIN_CACHE_DIR ?= /var/tmp/atlas/act_cache/tf
TF_STATE_DIR        ?= /var/tmp/atlas/terraform

LOCAL_RUNNER_DIR ?= tools/ci/local-runner
ACT_RUNNER_DIR   ?= tools/ci/act-runner

ATLASCTL_BIN ?= tools/atlasctl/bin/atlasctl

# Taskfiles (invoked via go-task)
SEAL_TASKFILE     ?= apps/seal/Taskfile.yml
ATLASCTL_TASKFILE ?= tools/atlasctl/Taskfile.yml

INCUS_SNAP_SCRIPT ?= tools/incus/incus-control.sh

# Zot registry cache (consumed by tools/incus/zot-image.sh)
ZOT_REMOTE      ?= ghcr-oci
ZOT_IMAGE_REF   ?= ghcr.io/project-zot/zot:v2.1.16
ZOT_IMAGE_ALIAS ?= zot-cache

# Snapshot name for incus-snap-* targets, e.g. make incus-snap-restore SNAP=my-snap
SNAP ?=

# App/group argument for atlasctl targets, e.g. make atlasctl-status ARGS=aldoshkineg/seal
ARGS ?=

# --- Phony targets ---------------------------------------------------------
.PHONY: help \
	zot-image stage-sync \
	ci-runner-up ci-runner-down ci-runner-logs \
	ci-runner-apply ci-runner-ci ci-runner-base ci-runner-middleware ci-runner-workload \
	ci-runner-destroy ci-runner-destroy-force \
	act-build act-ci act-stage-base act-stage-middleware act-stage-workload act-destroy act-destroy-force \
	argocd-login \
	seed-vault seed-gh \
	atlasctl-build atlasctl-test atlasctl-vet atlasctl-new seed-atlas atlasctl-list atlasctl-status \
	seal-build seal-push seal-dc-up seal-dc-down seal-dc-logs seal-unit \
	rbac-apply rbac-delete \
	test test-ca-gateway test-vault test-velero test-keda test-redis \
	test-network-policy test-db-backup test-seal test-argocd-rollout test-undeploy \
	validate validate-terraform validate-yaml validate-security pre-commit \
	preflight \
	seal-verify \
	incus-snap-create incus-snap-restore incus-snap-list incus-snap-delete \
	incus-vm-stop incus-vm-start

# --- Help ------------------------------------------------------------------
help:
	@echo "Available Targets:"
	@echo ""
	@echo "Local Run (act):"
	@echo "  act-ci           Run full CI pipeline (base+middleware+workload) via act"
	@echo "  act-stage-base   Run base stage (infra + vault seeds) via act"
	@echo "  act-stage-middleware  Sync platform layers (DB/MinIO/Vault/monitoring) via act"
	@echo "  act-stage-workload    Seed + sync workloads (seal) via act"
	@echo "  act-destroy      Destroy stage infrastructure via act (ci-destroy workflow)"
	@echo "  act-destroy-force  Hard teardown of stage (Incus/Talos + TF state) via ci-destroy-force workflow"
	@echo "  act-build        Build custom act runner image"
	@echo ""
	@echo "Runner (local runner):"
	@echo "  ci-runner-up        Start self-hosted GitHub runner (needs Docker+Incus)"
	@echo "  ci-runner-down      Stop and remove the runner container"
	@echo "  ci-runner-logs      Follow runner logs"
	@echo "  ci-runner-apply     Dispatch apply via runner (ci-base workflow)"
	@echo "  ci-runner-ci        Dispatch full CI via runner (ci-all workflow)"
	@echo "  ci-runner-base      Dispatch base stage via runner"
	@echo "  ci-runner-middleware Dispatch middleware stage via runner"
	@echo "  ci-runner-workload  Dispatch workload stage via runner"
	@echo "  ci-runner-destroy   Dispatch destroy via runner (ci-destroy workflow)"
	@echo "  ci-runner-destroy-force  Dispatch hard teardown via runner"
	@echo ""
	@echo "Cluster & Registry Cache (Incus/Zot):"
	@echo "  zot-image      Pull + import Zot image into Incus (required to start the project)"
	@echo "  stage-sync     Sync GitOps platform layers"
	@echo ""
	@echo "ArgoCD:"
	@echo "  argocd-login    Login to ArgoCD via CLI"
	@echo ""
	@echo "Vault & Secrets:"
	@echo "  seed-vault      Read .env + seed-mapping.conf, seed into Vault via port-forward"
	@echo "  seed-gh         Upload the whole .env as one GitHub Secret (ENV_FILE)"
	@echo ""
	@echo "Workloads (atlasctl):"
	@echo "  atlasctl-build  Build the atlasctl Go binary"
	@echo "  atlasctl-test   Run atlasctl unit tests"
	@echo "  atlasctl-vet    Run 'go vet' on atlasctl"
	@echo "  atlasctl-new    Scaffold a new workload (see: $(ATLASCTL_BIN) new --help)"
	@echo "  seed-atlas      Seed workload secrets into Vault"
	@echo "  atlasctl-list   List all registered workloads"
	@echo "  atlasctl-status Show status of a workload (e.g. make atlasctl-status ARGS=aldoshkineg/seal)"
	@echo ""
	@echo "Apps (seal):"
	@echo "  seal-build      Build all seal Docker images (api/worker/ui)"
	@echo "  seal-push       Tag + push seal images to GHCR (needs .env; TAG=git default)"
	@echo "  seal-dc-up      Start seal integration stack (docker compose)"
	@echo "  seal-dc-down    Stop seal integration stack"
	@echo "  seal-dc-logs    Follow seal integration stack logs"
	@echo "  seal-unit       Run seal Go unit tests"
	@echo ""
	@echo "Tests:"
	@echo "  test               Deploy and verify all platform tests"
	@echo "  test-ca-gateway    Deploy CA gateway test and verify TLS endpoint"
	@echo "  test-vault         Seed Vault, deploy injection pod, verify secrets"
	@echo "  test-velero        Test Velero backup/restore to S3"
	@echo "  test-keda          Test KEDA autoscaling via ConfigMap trigger"
	@echo "  test-redis         Test Redis availability/connectivity"
	@echo "  test-network-policy  Test NetworkPolicy isolation between pods"
	@echo "  test-db-backup     Test CNPG backup/restore to MinIO"
	@echo "  test-seal          Test Seal deployment (pods, API, documents, gateway)"
	@echo "  test-argocd-rollout  Test Argo Rollouts canary progression"
	@echo "  test-undeploy      Remove all test resources"
	@echo ""
	@echo "Quality:"
	@echo "  validate          Run fmt/validate checks (Terraform, Yamllint, Trivy)"
	@echo "  pre-commit        Run pre-commit hooks on all project files"
	@echo "  preflight         Verify local host readiness for act/runner pipelines"
	@echo ""
	@echo "Security & RBAC:"
	@echo "  rbac-apply      Apply RBAC policies (ClusterRoles, bindings)"
	@echo "  rbac-delete     Remove RBAC policies"
	@echo "  seal-verify       Verify Seal image signatures (cosign); TAG=vX.Y.Z"
	@echo ""
	@echo "Incus VM lifecycle:"
	@echo "  incus-snap-create   Snapshot all Talos VMs (SNAP=name optional)"
	@echo "  incus-snap-restore  Restore all Talos VMs from a snapshot (SNAP=name)"
	@echo "  incus-snap-list     List snapshots for all Talos VMs"
	@echo "  incus-snap-delete   Delete a named snapshot (SNAP=name)"
	@echo "  incus-vm-stop       Stop all Talos VMs (hard stop)"
	@echo "  incus-vm-start      Start all Talos VMs"

# --- Cluster & Registry Cache (Incus/Zot) ---------------------------------
# Terraform is driven through `act` (which runs terraform internally); the
# Zot cache is deployed directly here since it is a standalone Incus instance.
zot-image:
	./tools/incus/zot-image.sh ensure

stage-sync:
	./tools/ci/sync-layers.sh

# --- Runner (local runner) ------------------------------------------------
ci-runner-up:
	./$(LOCAL_RUNNER_DIR)/runner.sh up

ci-runner-down:
	./$(LOCAL_RUNNER_DIR)/runner.sh down

ci-runner-logs:
	./$(LOCAL_RUNNER_DIR)/runner.sh logs

ci-runner-apply:
	./$(LOCAL_RUNNER_DIR)/runner.sh apply

ci-runner-ci:
	./$(LOCAL_RUNNER_DIR)/runner.sh ci

ci-runner-base:
	./$(LOCAL_RUNNER_DIR)/runner.sh base

ci-runner-middleware:
	./$(LOCAL_RUNNER_DIR)/runner.sh middleware

ci-runner-workload:
	./$(LOCAL_RUNNER_DIR)/runner.sh workload

ci-runner-destroy:
	./$(LOCAL_RUNNER_DIR)/runner.sh destroy

ci-runner-destroy-force:
	./$(LOCAL_RUNNER_DIR)/runner.sh destroy-force

# --- Local Run (act) -------------------------------------------------------
act-build:
	$(ACT_RUNNER_DIR)/act-runner.sh build

act-ci:
	$(ACT_RUNNER_DIR)/act-runner.sh ci

act-stage-base:
	$(ACT_RUNNER_DIR)/act-runner.sh base

act-stage-middleware:
	$(ACT_RUNNER_DIR)/act-runner.sh middleware

act-stage-workload:
	$(ACT_RUNNER_DIR)/act-runner.sh workload

act-destroy:
	$(ACT_RUNNER_DIR)/act-runner.sh destroy

act-destroy-force:
	$(ACT_RUNNER_DIR)/act-runner.sh destroy-force

# --- ArgoCD ----------------------------------------------------------------
argocd-login:
	./tools/argocd-login.sh

# --- Vault & Secrets -------------------------------------------------------
seed-vault:
	@unset VAULT_ADDR; ./security/vault/seed-vault.sh

seed-gh:
	./security/vault/seed-gh.sh

# --- Workloads (atlasctl) --------------------------------------------------
atlasctl-build:
	go-task -t $(ATLASCTL_TASKFILE) build

atlasctl-test:
	go-task -t $(ATLASCTL_TASKFILE) test

atlasctl-vet:
	go-task -t $(ATLASCTL_TASKFILE) vet

atlasctl-new:
	@echo "Scaffold a new workload:"
	@echo "  $(ATLASCTL_BIN) new <app> --group <group> --repo <url> [options]"
	@echo "Example:"
	@echo "  $(ATLASCTL_BIN) new seal --group aldoshkineg --repo https://github.com/aldoshkineg/atlas-idp.git --repo-path charts/seal --helm"
	@echo "Build first: make atlasctl-build"

seed-atlas:
	$(ATLASCTL_BIN) seed $(ARGS)

atlasctl-list:
	$(ATLASCTL_BIN) list

atlasctl-status:
	$(ATLASCTL_BIN) status $(ARGS)

# --- Apps: Seal ------------------------------------------------------------
seal-build:
	go-task -t $(SEAL_TASKFILE) build-all

seal-push:
	go-task -t $(SEAL_TASKFILE) push-images

seal-dc-up:
	go-task -t $(SEAL_TASKFILE) dc-up

seal-dc-down:
	go-task -t $(SEAL_TASKFILE) dc-down

seal-dc-logs:
	go-task -t $(SEAL_TASKFILE) dc-logs

seal-unit:
	go-task -t $(SEAL_TASKFILE) test

# --- RBAC ------------------------------------------------------------------
rbac-apply:
	./tools/rbac/rbac.sh apply

rbac-delete:
	./tools/rbac/rbac.sh delete

# --- Tests -----------------------------------------------------------------
test: test-ca-gateway test-vault test-network-policy test-velero test-keda test-redis test-db-backup test-argocd-rollout test-seal

test-ca-gateway:
	./tests/scripts/gateway-test.sh

test-vault:
	./tests/scripts/vault-test.sh

test-velero:
	./tests/scripts/velero-test.sh

test-keda:
	./tests/scripts/keda-test.sh

test-redis:
	./tests/scripts/redis-test.sh

test-network-policy:
	./tests/scripts/network-policy-test.sh

test-db-backup:
	./tests/scripts/db-backup-test.sh

test-seal:
	./tests/scripts/seal-test.sh

test-argocd-rollout:
	./tests/scripts/argocd-rollout-test.sh

test-undeploy:
	./tests/scripts/test-undeploy.sh

# --- Quality ---------------------------------------------------------------
validate: validate-terraform validate-yaml validate-security

validate-terraform:
	./tools/ci/validate.sh terraform

validate-yaml:
	./tools/ci/validate.sh yaml

validate-security:
	./tools/ci/validate.sh security

pre-commit:
	./tools/ci/pre-commit.sh

# Verify the local host can actually run the act/runner pipelines before
# kicking them off (binaries, images, paths, .env/.secrets, daemons).
preflight:
	./tools/ci/preflight.sh

# --- Security --------------------------------------------------------------
seal-verify:
	./tools/security/seal-verify.sh $(TAG)

# --- Incus VM lifecycle ----------------------------------------------------
incus-snap-create:
	$(INCUS_SNAP_SCRIPT) create $(SNAP)

incus-snap-restore:
	@test -n "$(SNAP)" || (echo "Usage: make incus-snap-restore SNAP=<name>" >&2; exit 1)
	$(INCUS_SNAP_SCRIPT) restore $(SNAP)

incus-snap-list:
	$(INCUS_SNAP_SCRIPT) list

incus-snap-delete:
	@test -n "$(SNAP)" || (echo "Usage: make incus-snap-delete SNAP=<name>" >&2; exit 1)
	$(INCUS_SNAP_SCRIPT) delete $(SNAP)

incus-vm-stop:
	$(INCUS_SNAP_SCRIPT) stop

incus-vm-start:
	$(INCUS_SNAP_SCRIPT) start
