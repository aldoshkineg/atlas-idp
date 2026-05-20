# Atlas IDP

**Internal Developer Platform — GitOps-driven Kubernetes platform engineering**

Atlas IDP is a production-grade, cloud-native Internal Developer Platform (IDP) monorepo designed as a DevOps portfolio project. It demonstrates end-to-end platform engineering with Infrastructure as Code (IaC), GitOps delivery, CI/CD automation, observability, secrets management, security scanning, and disaster recovery — all running locally on [kind](https://kind.sigs.k8s.io/) Kubernetes clusters while following AWS production patterns.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CI/CD (GitLab CI)                          │
│   ┌─────────┐  ┌────────┐  ┌───────┐  ┌──────┐  ┌────────┐   │
│   │Validate │  │Security│  │ Build │  │ Kind │  │ Deploy │   │
│   └─────────┘  └────────┘  └───────┘  └──────┘  └────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴──────────────────────────────────┐
│                   GitOps (Argo CD)                              │
│   App-of-Apps: root → platform services → workloads             │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴──────────────────────────────────┐
│                Kubernetes Runtime (kind)                        │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐         │
│   │ Ingress  │ │ Metrics  │ │ Prom/    │ │ Vault    │         │
│   │  Nginx   │ │  Server  │ │ Grafana  │ │          │         │
│   └──────────┘ └──────────┘ └──────────┘ └──────────┘         │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐                       │
│   │  Cert    │ │  Velero  │ │  Backend │  Worker  Cron         │
│   │ Manager  │ │   (DR)   │ │   API    │                       │
│   └──────────┘ └──────────┘ └──────────┘                       │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴──────────────────────────────────┐
│                 Infrastructure (Terraform)                      │
│   Local-kind            AWS (planned)            Modules       │
│   ┌──────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│   │ kind cluster │  │ VPC · EKS · IRSA │  │ cluster        │  │
│   │ Argo CD helm │  │ S3 · EBS · AMP   │  │ networking     │  │
│   │ GitLab Runner│  │                  │  │ iam · storage  │  │
│   └──────────────┘  └──────────────────┘  │ addons         │  │
│                                            │ observability  │  │
│                                            └────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Category              | Tools                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| **Infrastructure**    | Terraform / OpenTofu                                                  |
| **Kubernetes**        | kind (local), EKS (planned)                                           |
| **GitOps**            | Argo CD                                                               |
| **CI/CD**             | GitLab CI · GitLab Runner (Docker)                                    |
| **Observability**     | Prometheus · Grafana · Loki (planned)                                 |
| **Secrets**           | HashiCorp Vault                                                       |
| **Security**          | Trivy · yamllint · RBAC · pre-commit hooks                            |
| **Backup / DR**       | Velero (planned)                                                      |
| **Ingress**           | ingress-nginx · cert-manager                                          |
| **Languages**         | HCL · YAML · Shell · Go (planned for apps)                            |

---

## Repository Structure

```
atlas-idp/
├── infra/                      # Infrastructure as Code (Terraform)
│   ├── bootstrap/argocd/       #   Day-0 Argo CD Helm install
│   ├── environments/
│   │   ├── local-kind/         #   Active: kind cluster + GitLab Runner
│   │   │   └── gitlab-runner/  #     Docker Compose · registration scripts
│   │   └── aws/                #   Planned: EKS production environment
│   └── modules/                #   Reusable Terraform modules
│       ├── cluster/            #     kind cluster metadata
│       ├── networking/         #     VPC · subnets · security groups (stub)
│       ├── iam/                #     IRSA / IAM roles (stub)
│       ├── storage/            #     S3 · PVC storage classes (stub)
│       ├── addons/             #     Cluster addons (stub)
│       └── observability/      #     Remote metrics/logs (stub)
├── clusters/                   # Kubernetes cluster lifecycle
│   ├── kind/                   #   kind cluster manifests
│   │   ├── cluster.yaml        #     Production-like: 1 CP + 2 workers
│   │   └── cluster-ci.yaml     #     CI: 1 CP + 1 worker
│   └── scripts/                #   Cluster management scripts
│       ├── create-cluster.sh   #     Create kind cluster
│       ├── destroy-cluster.sh  #     Delete kind cluster
│       ├── bootstrap-gitops.sh #     Day-0: Terraform + Argo CD root app
│       └── ci-kind-*.sh        #     CI pipeline helpers
├── gitops/                     # GitOps manifests (Argo CD)
│   ├── bootstrap/              #   App-of-Apps root and argocd self-mgmt
│   │   ├── root-app.yaml       #     Root Application (platform layer)
│   │   └── argocd/             #     Day-1 self-management manifests
│   └── workloads/              #   Workload Applications
│       └── application.yaml    #     Workloads app (backend-api, worker, cron)
├── apps/                       # Sample application code
│   ├── backend-api/            #   Backend API service (planned)
│   ├── worker/                 #   Worker service (planned)
│   ├── cronjob/                #   CronJob (planned)
│   └── charts/                 #   Helm charts (planned)
├── ci/                         # GitLab CI job definitions
│   ├── terraform.yml           #   Terraform validate
│   ├── security.yml            #   Trivy scans (IaC + container images)
│   ├── build.yml               #   Container image builds
│   ├── deploy.yml              #   Argo CD sync (manual)
│   └── kind.yml                #   Kind cluster lifecycle in CI
├── observability/              # Monitoring & alerting
│   ├── alerts/                 #   Prometheus custom alert rules
│   │   ├── custom-rule-1.yaml  #     HighErrorRate
│   │   └── custom-rule-2.yaml  #     HPAMaxedOut
│   └── dashboards/             #   Grafana dashboards (planned)
├── vault/                      # HashiCorp Vault configuration
│   ├── bootstrap/              #   Init, unseal, policy scripts
│   ├── policies/               #   Vault ACL policies
│   │   └── platform-read.hcl   #     Read-only access to platform secrets
│   └── kubernetes-auth/        #   Kubernetes auth method roles
│       └── role-backend-api.yaml
├── velero/                     # Disaster recovery (planned)
├── security/                   # Security tooling
│   ├── trivy/                  #   Trivy configuration
│   │   └── trivy.yaml
│   └── rbac/                   #   RBAC policies (planned)
├── docs/                       # Documentation
│   ├── runbooks/               #   Operational runbooks (planned)
│   └── diagrams/               #   Architecture diagrams (planned)
├── ai/                         # AI-assisted design specification
│   └── system-prompt.md        #   Full platform spec for AI agents
├── assets/diagrams/            # Diagram assets (planned)
├── Makefile                    # Developer workflow targets
├── .gitlab-ci.yml              # Root CI pipeline (5 stages)
├── .pre-commit-config.yaml     # Pre-commit hooks
├── .yamllint.yml               # YAML linting rules
└── .gitignore
```

---

## Quick Start

### Prerequisites

- [kind](https://kind.sigs.k8s.io/) v0.26+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.31+
- [Terraform](https://www.terraform.io/) v1.9+
- [Docker](https://www.docker.com/) (for GitLab Runner)
- [pre-commit](https://pre-commit.com/)
- [yamllint](https://github.com/adrienverge/yamllint)
- [Trivy](https://github.com/aquasecurity/trivy)

### 1. Create the cluster

```bash
make cluster-up
```

This provisions a 3-node kind cluster (1 control-plane + 2 workers) with ingress ports 80/443 mapped to the host.

### 2. Deploy Argo CD (Day-0 bootstrap)

```bash
make infra-init     # Terraform init for local-kind environment
make infra-plan     # Review the plan
make gitops-bootstrap  # Terraform apply → Argo CD install → root app
```

### 3. (Optional) Set up GitLab Runner locally

```bash
make secrets-init                      # Create .env from template
# Edit infra/environments/local-kind/gitlab-runner/.env with your tokens
make runner-up                         # Register + start GitLab Runner
```

### 4. Validate everything

```bash
make validate       # Terraform fmt, Trivy, yamllint
make pre-commit     # Pre-commit hooks on all files
```

### 5. Tear down

```bash
make runner-down    # Stop GitLab Runner
make cluster-down   # Delete kind cluster
```

---

## Makefile Targets

| Target               | Description                                         |
|----------------------|-----------------------------------------------------|
| `cluster-up`         | Create kind cluster                                 |
| `cluster-down`       | Delete kind cluster                                 |
| `infra-init`         | Terraform init (ENV=local-kind)                     |
| `infra-plan`         | Terraform plan (ENV=local-kind)                     |
| `gitops-bootstrap`   | Install Argo CD (day-0) and apply root app          |
| `validate`           | Run fmt, Trivy, yamllint checks                     |
| `pre-commit`         | Run pre-commit on all files                         |
| `secrets-init`       | Copy `.env.example` → `.env`                        |
| `runner-create-api`  | Create runner via GitLab API                        |
| `runner-register`    | Register GitLab Runner                              |
| `runner-up`          | Register + start GitLab Runner container            |
| `runner-down`        | Stop GitLab Runner container                        |
| `runner-logs`        | Follow GitLab Runner logs                           |

---

## CI/CD Pipeline

The GitLab CI pipeline consists of **5 stages**:

| Stage       | Jobs                                        | Trigger                     |
|-------------|---------------------------------------------|-----------------------------|
| `validate`  | Terraform fmt, init, validate               | MR / default branch         |
| `security`  | Trivy IaC scan, Trivy image scan            | MR / default branch         |
| `build`     | Docker image build (backend-api, worker)    | `apps/**` changes on main   |
| `kind`      | Provision kind cluster, smoke tests, delete | Tagged `atlas-idp` runners  |
| `deploy`    | Argo CD sync (manual)                       | Manual approval             |

### Local CI Pipeline

Run the full pipeline on your local kind cluster using a GitLab Runner registered via `make runner-up`. The pipeline uses resource group `local-kind` to prevent concurrent runs.

---

## Observability

### Alert Rules

| Rule              | Description                                              | Severity |
|-------------------|----------------------------------------------------------|----------|
| `HighErrorRate`   | >5% of HTTP requests return 5xx for 5 minutes            | critical |
| `HPAMaxedOut`     | HPA current replicas == max replicas for 15 minutes      | warning  |

---

## Security

### Pre-commit Hooks

- Trailing whitespace · End-of-file fixes · YAML validation
- Merge conflict detection · Private key detection
- Terraform fmt · Terraform validate · Terraform docs
- yamllint · Trivy (HIGH/CRITICAL)

### Trivy

Scans all IaC (`infra/`, `gitops/`, `vault/`, `velero/`) and container images for HIGH and CRITICAL severity vulnerabilities.

### Vault

HashiCorp Vault manages secrets with fine-grained ACL policies. The `platform-read` policy grants read/list access to `secret/data/platform/*`. Kubernetes auth is configured for the `backend-api` service account.

---

## Environments

### `local-kind` (Active)

- **Cluster**: kind (1 control-plane + 2 workers)
- **State**: Local filesystem
- **GitOps**: Argo CD installed via Terraform Helm provider
- **Runner**: Docker Compose GitLab Runner

### `aws` (Planned)

- **Cluster**: Amazon EKS
- **Networking**: VPC · subnets · security groups
- **IAM**: IRSA roles for service accounts
- **Storage**: S3 buckets · EBS CSI driver
- **Observability**: AMP (metrics) · AMG (Grafana)

---

## Project Status

| Component              | Status          |
|------------------------|-----------------|
| Terraform modules      | Scaffolded      |
| kind clusters          | ✅ Complete     |
| Argo CD bootstrap      | ✅ Complete     |
| GitLab CI pipeline     | ✅ Complete     |
| GitLab Runner          | ✅ Complete     |
| Pre-commit hooks       | ✅ Complete     |
| Prometheus alert rules | ✅ Complete     |
| Vault config           | ✅ Complete     |
| Trivy scanning         | ✅ Complete     |
| Application code       | 📋 Planned      |
| Helm charts            | 📋 Planned      |
| Velero / DR            | 📋 Planned      |
| AWS environment        | 📋 Planned      |
| Grafana dashboards     | 📋 Planned      |
| Runbooks               | 📋 Planned      |

---

## License

This project is open source and available under the [MIT License](LICENSE).

