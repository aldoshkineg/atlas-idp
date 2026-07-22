.PHONY: help cluster-up cluster-down cluster-ci-up cluster-ci-down \
	infra-init infra-plan infra-apply cluster-nuke gitops-bootstrap validate pre-commit \
	ci-cache-up ci-cache-purge ci-runner-up ci-runner-down ci-runner-status ci-runner-logs \
	argocd-login vault-seed-from-env github-secrets-ca seed-ca \
	atlasctl atlasctl-seed atlasctl-list \
	test test-ca-gateway test-vault test-velero test-network-policy test-db-backup test-argocd-rollout test-undeploy \
	act-build act-ci act-stage-base act-stage-middleware act-stage-workload act-destroy \
	incus-snap-create incus-snap-restore incus-snap-list incus-snap-delete \
	incus-vm-stop incus-vm-start

CLUSTER_NAME     ?= atlas-idp
KIND_CONFIG      ?= clusters/kind/cluster.yaml
CI_CLUSTER       ?= atlas-idp-ci
ENV              ?= dev

# Auto-load .env if present (local B2 credentials etc.)
-include .env
export

# Terraform provider plugin cache
TF_PLUGIN_CACHE_DIR ?= /var/tmp/atlas/act_cache/tf
TF_STATE_DIR ?= /var/tmp/atlas/terraform

# Local CI / Automation Directories
LOCAL_RUNNER_DIR ?= tools/ci/local-runner
ACT_RUNNER_DIR   ?= tools/ci/act-runner

help:
	@echo "Available Targets:"
	@echo "  cluster-up        Create main kind cluster"
	@echo "  cluster-down      Delete main kind cluster"
	@echo "  cluster-nuke      Remove Zot container, delete kind cluster, wipe Terraform state"
	@echo "  cluster-ci-up     Provision local CI-specific kind cluster"
	@echo "  cluster-ci-down   Tear down local CI-specific kind cluster"
	@echo "  infra-init        Terraform init (ENV=$(ENV))"
	@echo "  infra-plan        Terraform plan (ENV=$(ENV))"
	@echo "  infra-apply       Initialize and Apply Terraform in infra/environments/dev"
	@echo "  gitops-bootstrap  Install Argo CD (day-0) and apply root app"
	@echo "  validate          Run fmt/validate checks (Terraform, Trivy, Yamllint)"
	@echo "  pre-commit        Run pre-commit hooks on all project files"
	@echo ""
	@echo "Local CI & Registry Cache Subsystem:"
	@echo "  ci-cache-up       Deploy Zot cache (via Terraform; delegates to infra-apply)"
	@echo "  ci-cache-purge    Stop and remove Zot container (cache data preserved)"
	@echo "  ci-runner-up      Fetch fresh token via 'gh' and start local GitHub runner"
	@echo "  ci-runner-down    Stop and remove local GitHub runner container"
	@echo "  ci-runner-status  Check status of local GitHub runner container"
	@echo "  ci-runner-logs    Follow logs from the local GitHub runner container"
	@echo ""
	@echo "Act (Local CI Runner):"
	@echo "  act-build           Build custom act runner image (parses action.yml for tool versions)"
	@echo "  act-ci              Run full CI pipeline (ci-all: base+middleware+workloads) via act"
	@echo "  act-stage-base      Run base stage (ci-base: infra + vault seeds) via act"
	@echo "  act-stage-middleware  Sync platform layers (ci-middleware: DB/MinIO/Vault/monitoring) via act"
	@echo "  act-stage-workload    Seed + sync workloads (ci-workload: seal) via act"
	@echo "  act-destroy         Destroy stage infrastructure (ci-destroy) via act"
	@echo ""
	@echo "ArgoCD:"
	@echo "  argocd-login      Login to ArgoCD via CLI"
	@echo ""
	@echo "Vault:"
	@echo "  vault-seed-from-env     Read .env + seed-mapping.conf, seed into Vault via port-forward"
	@echo ""
	@echo "Tests:"
	@echo "  test             Deploy and verify all platform tests"
	@echo "  test-ca-gateway  Deploy CA gateway test and verify TLS endpoint"
	@echo "  test-vault       Seed Vault, deploy injection pod, verify secrets"
	@echo "  test-velero      Test Velero backup/restore to S3"
	@echo "  test-keda        Test KEDA autoscaling via ConfigMap trigger"
	@echo "  test-network-policy  Test NetworkPolicy isolation between pods"
	@echo "  test-db-backup       Test CNPG backup/restore to MinIO"
	@echo "  test-seal            Test Seal deployment (pods, API, documents, gateway)"
	@echo "  test-argocd-rollout  Test Argo Rollouts canary progression"
	@echo "  test-undeploy    Remove all test resources"
	@echo ""
	@echo "Atlas Workload Management:"
	@echo "  atlasctl-new    Scaffold a new workload (golden path)"
	@echo "  atlasctl-seed   Seed workload secrets into Vault"
	@echo "  atlasctl-list   List all registered workloads"
	@echo ""
	@echo "RBAC:"
	@echo "  rbac-apply        Apply RBAC policies (ClusterRoles, bindings)"
	@echo "  rbac-delete       Remove RBAC policies"
	@echo ""
	@echo "GitHub Secrets:"
	@echo "  github-secrets-ca  Add root CA cert and key to GitHub secrets (ATLAS_CA_CRT, ATLAS_CA_KEY)"
	@echo ""
	@echo "CA Certificates:"
	@echo "  seed-ca           Create atlas-ca-secret for cert-manager from security/certs/"
	@echo ""
	@echo "Incus Snapshots:"
	@echo "  incus-snap-create    Snapshot all Talos VMs (for rollback before destructive changes)"
	@echo "  incus-snap-restore   Restore all Talos VMs from a snapshot (stops VMs, restores, starts)"
	@echo "  incus-snap-list      List snapshots for all Talos VMs"
	@echo "  incus-snap-delete    Delete a named snapshot from all Talos VMs"
	@echo "  incus-vm-stop        Stop all Talos VMs (hard stop)"
	@echo "  incus-vm-start       Start all Talos VMs"
	@echo ""

# --- Infrastructure Management ---
cluster-up:
	./clusters/scripts/create-cluster.sh

cluster-down:
	./clusters/scripts/destroy-cluster.sh

cluster-nuke:
	@echo "--> Removing Zot cache container..."
	-docker rm -f kind-zot-registry
	@echo "--> Force deleting Kind cluster '$(CLUSTER_NAME)'..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "--> Wiping local Terraform state..."
	sudo rm -rf $(TF_STATE_DIR)
	@echo "--> State wiped"

cluster-ci-up:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-provision.sh

cluster-ci-down:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-down.sh

infra-init:
	mkdir -p $(TF_PLUGIN_CACHE_DIR) $(TF_STATE_DIR)
	cd infra/environments/$(ENV) && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform init

infra-plan:
	cd infra/environments/$(ENV) && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform plan

infra-apply:
	@echo "--> Running initialization in dev environment..."
	mkdir -p $(TF_PLUGIN_CACHE_DIR) $(TF_STATE_DIR)
	cd infra/environments/dev && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform init
	@echo "--> Applying infrastructure changes..."
	cd infra/environments/dev && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform apply -auto-approve
	@echo "--> Seeding CA certificate into cluster..."
	$(MAKE) seed-ca

gitops-bootstrap:
	./clusters/scripts/bootstrap-gitops.sh

# --- ArgoCD ---
argocd-login:
	@chmod +x tools/argocd-login.sh
	./tools/argocd-login.sh

# --- Vault ---
# Read .env + seed-mapping.conf, resolve env vars, seed into Vault via port-forward
vault-seed-from-env:
	@unset VAULT_ADDR; ./security/vault/seed-from-env.sh

# --- Atlas Workload Management ---
ATLASCTL_BIN ?= tools/atlasctl/bin/atlasctl

atlasctl:
	@echo "Usage: make atlasctl-{new,seed,list,build,test}"
	@echo "  atlasctl-new  <args>   Create a new workload (via atlasctl Go binary)"
	@echo "  atlasctl-seed          Seed all workload secrets into Vault"
	@echo "  atlasctl-list          List all registered workloads"
	@echo "  atlasctl-build         Build atlasctl Go binary"
	@echo "  atlasctl-test          Run atlasctl unit tests"

atlasctl-build:
	go-task -t tools/atlasctl/Taskfile.yml build

atlasctl-test:
	go-task -t tools/atlasctl/Taskfile.yml test

atlasctl-vet:
	go-task -t tools/atlasctl/Taskfile.yml vet

atlasctl-new:
	@echo "Run: $(ATLASCTL_BIN) new <app> --group <group> --repo <url> [options]"
	@echo "Example:"
	@echo "  $(ATLASCTL_BIN) new seal --group aldoshkineg --repo https://github.com/aldoshkineg/atlas-idp.git --repo-path charts/seal --helm"
	@echo ""
	@echo "Build first: make atlasctl-build"

atlasctl-seed:
	$(ATLASCTL_BIN) seed $(filter-out $@,$(MAKECMDGOALS))

atlasctl-list:
	$(ATLASCTL_BIN) list

atlasctl-status:
	$(ATLASCTL_BIN) status $(filter-out $@,$(MAKECMDGOALS))

# --- Tests ---
test-ca-gateway:
	./tests/scripts/gateway-test.sh

test-vault:
	./tests/scripts/vault-test.sh

test: test-ca-gateway test-vault test-network-policy test-velero test-keda test-redis test-db-backup test-argocd-rollout test-seal

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

# --- RBAC ---
rbac-apply:
	kubectl apply -f security/rbac/

rbac-delete:
	kubectl delete -f security/rbac/ --ignore-not-found

# --- GitHub Secrets ---
github-secrets-ca:
	@echo "--> Adding root CA certificate to GitHub secrets (ATLAS_CA_CRT)..."
	gh secret set ATLAS_CA_CRT < security/certs/ca.crt
	@echo "--> Adding root CA key to GitHub secrets (ATLAS_CA_KEY)..."
	gh secret set ATLAS_CA_KEY < security/certs/ca.key
	@echo "--> CA certificate and key added to GitHub secrets successfully"

seed-ca:
	@echo "--> Setting kubeconfig from kind cluster..."
	@kind export kubeconfig --name $(CLUSTER_NAME) 2>/dev/null || true
	@echo "--> Ensuring cert-manager namespace exists..."
	kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
	@echo "--> Creating atlas-ca-secret in cert-manager namespace..."
	kubectl create secret tls atlas-ca-secret -n cert-manager \
		--cert=security/certs/ca.crt \
		--key=security/certs/ca.key \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "--> CA secret seeded successfully. ClusterIssuer atlas-ca-issuer should become Healthy."

# --- Quality Assurance & Linting ---
validate: validate-terraform validate-yaml validate-security

validate-terraform:
	@echo "==> Running Terraform format check..."
	terraform fmt -check -recursive infra/
	@echo "==> Running Terraform validate..."
	mkdir -p $(TF_PLUGIN_CACHE_DIR)
	cd infra/environments/dev && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform init -backend=false && TF_PLUGIN_CACHE_DIR=$(TF_PLUGIN_CACHE_DIR) terraform validate

validate-yaml:
	@echo "==> Running YAML lint..."
	@command -v yamllint >/dev/null && yamllint -c .yamllint.yml gitops/ observability/ security/ tests/ || echo "yamllint not installed, skip"

validate-security:
	@echo "==> Running security scan..."
	@command -v trivy >/dev/null && (trivy config --config security/trivy/trivy.yaml --severity HIGH,CRITICAL infra/; trivy config --config security/trivy/trivy.yaml --severity HIGH,CRITICAL gitops/) || echo "trivy not installed, skip"

pre-commit:
	pre-commit run --all-files

# --- Cosign image signature verification ---
# Verifies seal-api / seal-worker / seal-ui against security/cosign/cosign.pub.
# Requires cosign in PATH; override the tag with TAG=vX.Y.Z
seal-verify:
	@echo "--> Verifying Seal image signatures (tag: $(or $(TAG),v0.50.0))"
	@for svc in seal-api seal-worker seal-ui; do \
	  cosign verify --key security/cosign/cosign.pub "ghcr.io/aldoshkineg/$${svc}:$(or $(TAG),v0.50.0)" || exit 1; \
	done

# --- Local CI & Registry Cache Subsystem ---
# The Zot image is NOT managed by Terraform. It is pulled once, outside
# Terraform, via `make zot-image` (which copies ghcr.io/project-zot/zot into
# Incus under the alias "zot-cache" only when that alias is missing). Run
# `make zot-image` before `make act-stage-base` on a fresh host.
ZOT_REMOTE      ?= ghcr-oci
ZOT_IMAGE_REF   ?= ghcr.io/project-zot/zot:v2.1.16
ZOT_IMAGE_ALIAS ?= zot-cache

zot-image:
	@echo "--> Ensuring Zot image '$(ZOT_IMAGE_ALIAS)' is present in Incus..."
	@incus remote list 2>/dev/null | grep -qw "$(ZOT_REMOTE)" || \
		incus remote add "$(ZOT_REMOTE)" https://ghcr.io --protocol oci --public
	@if incus image list 2>/dev/null | grep -qw "$(ZOT_IMAGE_ALIAS)"; then \
		echo "    '$(ZOT_IMAGE_ALIAS)' already present, skipping copy"; \
	else \
		echo "    copying $(ZOT_IMAGE_REF) ..."; \
		incus image copy "$(ZOT_REMOTE):project-zot/zot:v2.1.16" --alias "$(ZOT_IMAGE_ALIAS)"; \
	fi

ci-cache-up: infra-apply

ci-cache-purge:
	@echo "--> Stopping and removing Zot container..."
	-docker rm -f kind-zot-registry 2>/dev/null || true
	@echo "--> Zot container removed. Cache data preserved at /var/tmp/atlas/zot_cache"

ci-runner-up:
	@chmod +x $(LOCAL_RUNNER_DIR)/setup-runner.sh
	cd $(LOCAL_RUNNER_DIR) && ./setup-runner.sh

ci-runner-down:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml down

ci-runner-status:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml ps

ci-runner-logs:
	docker compose -f $(LOCAL_RUNNER_DIR)/docker-compose.yml logs -f

# --- Act (Local CI Runner) ---
# Each target drives a single GitHub workflow via act (tools/ci/act-runner).
# Build the runner image once with `make act-build` (or pass STAGE_BUILD).
act-build:
	tools/ci/act-runner/act-runner.sh build

# Full CI pipeline (ci-all.yaml: base -> middleware -> workloads) via act.
act-ci:
	tools/ci/act-runner/act-runner.sh ci

# Base stage only (ci-base.yaml: tools + checks + terraform apply + vault seeds).
act-stage-base:
	tools/ci/act-runner/act-runner.sh base

# Platform middleware (ci-middleware.yaml: storage/security/delivery/observability).
# Requires a running base stage (make act-stage-base).
act-stage-middleware:
	tools/ci/act-runner/act-runner.sh middleware

# Workloads (ci-workload.yaml: seed + sync seal). Requires the middleware stage up.
act-stage-workload:
	tools/ci/act-runner/act-runner.sh workload

act-destroy:
	tools/ci/act-runner/act-runner.sh destroy

stage-destroy:
	./tools/ci/stage-terrafrom-destroy.sh

stage-sync:
	./tools/ci/sync-layers.sh

# --- Incus Snapshots ---
INCUS_SNAP_SCRIPT ?= tools/incus/incus-control.sh

incus-snap-create:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) create $(filter-out $@,$(MAKECMDGOALS))

incus-snap-restore:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) restore $(filter-out $@,$(MAKECMDGOALS))

incus-snap-list:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) list

incus-snap-delete:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) delete $(filter-out $@,$(MAKECMDGOALS))

incus-vm-stop:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) stop

incus-vm-start:
	@chmod +x $(INCUS_SNAP_SCRIPT)
	$(INCUS_SNAP_SCRIPT) start

# Swallow extra args passed to incus-snap targets (e.g. make incus-snap-restore my-snap)
%:;
