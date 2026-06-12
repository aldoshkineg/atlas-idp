.PHONY: help cluster-up cluster-down cluster-ci-up cluster-ci-down \
	infra-init infra-plan infra-apply cluster-nuke gitops-bootstrap validate pre-commit \
	ci-cache-up ci-cache-purge ci-runner-up ci-runner-down ci-runner-status ci-runner-logs \
	argocd-login vault-seed github-secrets-ca seed-ca \
	test test-gateway test-vault test-seed test-velero test-network-policy test-undeploy \
	act-build act-ci

CLUSTER_NAME     ?= atlas-idp
KIND_CONFIG      ?= clusters/kind/cluster.yaml
CI_CLUSTER       ?= atlas-idp-ci
ENV              ?= dev

# Auto-load .env if present (local B2 credentials etc.)
-include .env
export

# Local CI / Automation Directories
LOCAL_RUNNER_DIR ?= clusters/kind/ci/local-runner
ZOT_DIR          ?= clusters/kind/ci/zot-kind-cache
ACT_RUNNER_DIR   ?= clusters/kind/ci/act-runner

help:
	@echo "Available Targets:"
	@echo "  cluster-up        Create main kind cluster"
	@echo "  cluster-down      Delete main kind cluster"
	@echo "  cluster-nuke      Force/Hard delete kind cluster via CLI and wipe local+remote tfstate"
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
	@echo "  ci-cache-up       Deploy/verify Zot local registry proxy cache"
	@echo "  ci-cache-purge    Wipe the Zot container registry completely"
	@echo "  ci-runner-up      Fetch fresh token via 'gh' and start local GitHub runner"
	@echo "  ci-runner-down    Stop and remove local GitHub runner container"
	@echo "  ci-runner-status  Check status of local GitHub runner container"
	@echo "  ci-runner-logs    Follow logs from the local GitHub runner container"
	@echo ""
	@echo "Act (Local CI Runner):"
	@echo "  act-build         Build custom act runner Docker image"
	@echo "  act-ci            Run CI workflow via act"
	@echo ""
	@echo "ArgoCD:"
	@echo "  argocd-login      Login to ArgoCD via CLI"
	@echo ""
	@echo "Vault:"
	@echo "  vault-seed        Seed test secrets into Vault (run after vault is healthy)"
	@echo ""
	@echo "Tests:"
	@echo "  test             Deploy all tests + seed Vault secrets"
	@echo "  test-gateway     Deploy gateway test (HTTPRoute + certificate)"
	@echo "  test-vault       Deploy Vault injection test"
	@echo "  test-seed        Seed test secrets into Vault"
	@echo "  test-velero      Test Velero backup/restore to S3"
	@echo "  test-network-policy  Test NetworkPolicy isolation between pods"
	@echo "  test-undeploy    Remove all test resources"
	@echo ""
	@echo "RBAC:"
	@echo "  rbac-apply        Apply RBAC policies (ClusterRoles, bindings)"
	@echo "  rbac-delete       Remove RBAC policies"
	@echo ""
	@echo "GitHub Secrets:"
	@echo "  github-secrets-ca  Add root CA cert and key to GitHub secrets (DEV_CA_CRT, DEV_CA_KEY)"
	@echo ""
	@echo "CA Certificates:"
	@echo "  seed-ca           Create dev-ca-secret for cert-manager from clusters/kind/certs/"

# --- Infrastructure Management ---
cluster-up:
	./clusters/scripts/create-cluster.sh

cluster-down:
	./clusters/scripts/destroy-cluster.sh

cluster-nuke:
	@echo "--> Force deleting Kind cluster '$(CLUSTER_NAME)'..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "--> Wiping ALL resources from remote S3 state..."
	cd infra/environments/dev && terraform init -backend-config=backend-s3.hcl -reconfigure 2>/dev/null && terraform state rm $$(terraform state list 2>/dev/null) 2>/dev/null || true
	@echo "--> Wiping local Terraform state files for dev environment..."
	rm -f infra/environments/dev/terraform.tfstate*

cluster-ci-up:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-provision.sh

cluster-ci-down:
	CLUSTER_NAME=$(CI_CLUSTER) ./clusters/scripts/ci-kind-down.sh

infra-init:
	cd infra/environments/$(ENV) && terraform init -backend-config=backend-s3.hcl

infra-plan:
	cd infra/environments/$(ENV) && terraform plan

infra-apply:
	@echo "--> Running initialization in dev environment..."
	cd infra/environments/dev && terraform init -backend-config=backend-s3.hcl
	@echo "--> Applying infrastructure changes..."
	cd infra/environments/dev && terraform apply -auto-approve
	@echo "--> Seeding CA certificate into cluster..."
	$(MAKE) seed-ca

gitops-bootstrap:
	./clusters/scripts/bootstrap-gitops.sh

# --- ArgoCD ---
argocd-login:
	@chmod +x clusters/kind/ci/argocd-login.sh
	./clusters/kind/ci/argocd-login.sh

# --- Vault ---
vault-seed:
	./tests/vault/seed.sh

# --- Tests ---
test-gateway:
	kubectl apply -f tests/gateway/namespace.yaml
	kubectl apply -f tests/gateway/app.yaml
	kubectl apply -f tests/gateway/certificate.yaml

test-vault:
	kubectl apply -f tests/vault

test-seed: test-vault
	./tests/scripts/seed.sh

test: test-gateway test-seed test-velero test-check

test-check:
	./tests/scripts/check.sh

test-velero:
	./tests/scripts/velero-test.sh

test-network-policy:
	kubectl apply -f tests/network-policy
	./tests/scripts/network-policy-test.sh

test-undeploy:
	kubectl delete -f tests/vault --ignore-not-found
	kubectl delete -f tests/gateway --ignore-not-found
	kubectl delete -f tests/network-policy --ignore-not-found
	kubectl delete pod -n testing -l app=backup-test --ignore-not-found 2>/dev/null || true
	kubectl delete pvc -n testing -l app=backup-test --ignore-not-found 2>/dev/null || true
	kubectl delete sc csi-hostpath-sc --ignore-not-found 2>/dev/null || true

# --- RBAC ---
rbac-apply:
	kubectl apply -f security/rbac/

rbac-delete:
	kubectl delete -f security/rbac/ --ignore-not-found

# --- GitHub Secrets ---
github-secrets-ca:
	@echo "--> Adding root CA certificate to GitHub secrets (DEV_CA_CRT)..."
	gh secret set DEV_CA_CRT < clusters/kind/certs/ca.crt
	@echo "--> Adding root CA key to GitHub secrets (DEV_CA_KEY)..."
	gh secret set DEV_CA_KEY < clusters/kind/certs/ca.key
	@echo "--> CA certificate and key added to GitHub secrets successfully"

seed-ca:
	@echo "--> Setting kubeconfig from kind cluster..."
	@kind export kubeconfig --name $(CLUSTER_NAME) 2>/dev/null || true
	@echo "--> Ensuring cert-manager namespace exists..."
	kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
	@echo "--> Creating dev-ca-secret in cert-manager namespace..."
	kubectl create secret tls dev-ca-secret -n cert-manager \
		--cert=clusters/kind/certs/ca.crt \
		--key=clusters/kind/certs/ca.key \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "--> CA secret seeded successfully. ClusterIssuer dev-ca-issuer should become Healthy."

# --- Quality Assurance & Linting ---
validate: validate-terraform validate-yaml validate-security

validate-terraform:
	@echo "==> Running Terraform format check..."
	terraform fmt -check -recursive infra/
	@echo "==> Running Terraform validate..."
	cd infra/environments/dev && terraform init -backend=false && terraform validate

validate-yaml:
	@echo "==> Running YAML lint..."
	@command -v yamllint >/dev/null && yamllint -c .yamllint.yml gitops/ observability/ security/ tests/ || echo "yamllint not installed, skip"

validate-security:
	@echo "==> Running security scan..."
	@command -v trivy >/dev/null && (trivy config --severity HIGH,CRITICAL infra/; trivy config --severity HIGH,CRITICAL gitops/) || echo "trivy not installed, skip"

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

# --- Act (Local CI Runner) ---
act-build:
	docker build -t act-runner:latest $(ACT_RUNNER_DIR)

act-ci:
	act -W .github/workflows/ci.yaml \
		--container-options "-v $(PWD)/clusters/kind/ci/act-runner/cache/tf:/opt/terraform/plugin-cache" \
		--container-options "-v $(PWD)/clusters/kind/ci/act-runner/cache/home:/root/.cache" \
		-s DEV_CA_CRT="$$(cat clusters/kind/certs/ca.crt)" \
		-s DEV_CA_KEY="$$(cat clusters/kind/certs/ca.key)"
