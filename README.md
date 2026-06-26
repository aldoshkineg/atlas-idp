# Atlas IDP

**Internal Developer Platform — GitOps-driven Kubernetes platform engineering**

Atlas IDP is a production-grade, cloud-native Internal Developer Platform (IDP) monorepo designed as a DevOps portfolio project. It demonstrates end-to-end platform engineering with Infrastructure as Code (IaC), GitOps delivery, CI/CD automation, observability, secrets management, security scanning, and disaster recovery — all running locally on [kind](https://kind.sigs.k8s.io/) Kubernetes clusters while following AWS production patterns.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   CI/CD (GitHub Actions)                        │
│   ┌─────────┐  ┌────────┐  ┌───────┐  ┌──────┐  ┌────────┐      │
│   │Validate │  │Security│  │ Build │  │ Kind │  │ Deploy │      │
│   └─────────┘  └────────┘  └───────┘  └──────┘  └────────┘      │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────────┐
│                   GitOps (Argo CD)                              │
│   App-of-Apps: root → platform services → workloads             │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────────┐
│                Kubernetes Runtime (kind)                        │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│   │ Gateway  │ │ Metrics  │ │ Prom/    │ │ Vault    │           │
│   │   API    │ │  Server  │ │ Grafana  │ │          │           │
│   └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐                        │
│   │  Cert    │ │  Velero  │ │  Backend │  Worker  Cron          │
│   │ Manager  │ │   (DR)   │ │   API    │                        │
│   └──────────┘ └──────────┘ └──────────┘                        │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────────┐
│                 Infrastructure (Terraform)                      │
│   Local-kind (dev)      AWS (planned)            Modules        │
│   ┌──────────────┐  ┌──────────────────┐  ┌────────────────┐    │
│   │ kind cluster │  │ VPC · EKS · IRSA │  │ kind           │    │
│   │ Argo CD helm │  │ S3 · EBS · AMP   │  │ argocd-boot    │    │
│   │ GH Actions   │  │                  │  │ networking     │    │
│   └──────────────┘  └──────────────────┘  │ iam · storage  │    │
│                                           │ addons         │    │
│                                           └────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Category           | Tools                                      |
| ------------------ | ------------------------------------------ |
| **Infrastructure** | Terraform / OpenTofu                       |
| **Kubernetes**     | kind (local), EKS                          |
| **GitOps**         | Argo CD                                    |
| **CI/CD**          | GitHub Actions                             |
| **Observability**  | Prometheus · Grafana · Loki                |
| **Secrets**        | HashiCorp Vault                            |
| **Security**       | Trivy · yamllint · RBAC · pre-commit hooks |
| **Backup / DR**    | Velero                                     |
| **Ingress**        | gateway-api · cert-manager                 |
| **Languages**      | HCL · YAML · Shell                         |

---

## Repository Structure

```
atlas-idp/
├── .github/
│   ├── workflows/
│   │   ├── ci.yaml             # Platform CI: checks + terraform-kind deploy
│   │   └── cleanup-local.yaml  # Manual KinD cluster cleanup
│   ├── actions/
│   │   ├── tools/              #   Install CLI tools (terraform, kubectl, kind, trivy)
│   │   ├── checks/             #   terraform fmt/validate, yamllint, trivy
│   │   ├── terraform-kind/     #   kind cluster + Argo CD bootstrap
│   │   └── terraform-eks/      #   EKS stub (not implemented)
│   └── scripts/
│       └── install-tools.sh    #   Tool installation helper
├── infra/                      # Infrastructure as Code (Terraform)
│   ├── environments/
│   │   ├── dev/                #   ACTIVE: kind cluster + Argo CD bootstrap
│   │   └── aws/                #   Planned: EKS production environment
│   └── modules/                #   Reusable Terraform modules
│       ├── kind/               #     kind cluster (tehcyx/kind provider)
│       ├── argocd-bootstrap/   #     Day-0 Argo CD Helm install
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
│   ├── platform/               #   Platform-layer Applications
│   │   ├── gateway-api.yaml   #     Gateway API controller
│   │   ├── cert-manager.yaml   #     TLS certificate management
│   │   ├── metrics-server.yaml #     Resource metrics (HPA)
│   │   └── monitoring.yaml     #     kube-prometheus-stack
│   └── workloads/              #   Workload Applications
│       └── application.yaml    #     Workloads app (backend-api, worker, cron)
├── apps/                       # Seal project
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
├── Makefile                    # Developer workflow targets
├── TODO.md                     # Implementation roadmap
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

### 1. Configure GitHub repository URL

**IMPORTANT:** Before running Terraform, replace placeholder URLs:

```bash
# Edit infra/environments/dev/main.tf
# Change: https://github.com/aldoshkineg/atlas-idp
# To:     https://github.com/your-org/your-repo

# Edit gitops/bootstrap/root-app.yaml
# Change: https://github.com/aldoshkineg/atlas-idp.git
# To:     https://github.com/your-org/your-repo.git
```

### 2. Deploy cluster + Argo CD (Day-0 bootstrap)

```bash
cd infra/environments/dev
terraform init
terraform plan
terraform apply -auto-approve
```

This will:

1. Create a 3-node kind cluster (1 CP + 2 workers)
2. Install Argo CD via Helm
3. Apply root Application CR
4. Argo CD syncs all platform services automatically

### 3. Access Argo CD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Access UI
open http://localhost:30080
# Username: admin
# Password: <from above>
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

| Target         | Description                       |
| -------------- | --------------------------------- |
| `cluster-up`   | Create kind cluster               |
| `cluster-down` | Delete kind cluster               |
| `infra-init`   | Terraform init (ENV=dev, default) |
| `infra-plan`   | Terraform plan (ENV=dev, default) |
| `validate`     | Run fmt, Trivy, yamllint checks   |
| `pre-commit`   | Run pre-commit on all files       |

---

## CI/CD Pipeline

GitHub Actions workflows (`.github/workflows/`):

| Workflow             | Trigger          | Purpose                                                  |
| -------------------- | ---------------- | -------------------------------------------------------- |
| `ci.yaml`            | push, PR, manual | Unified CI: tools → checks → terraform-kind deploy       |
| `cleanup-local.yaml` | manual           | Aggressive cleanup: delete KinD cluster, remove TF state |

### Composite Actions Architecture

The CI uses **composite actions** for reusability:

| Action                    | Purpose                                                       |
| ------------------------- | ------------------------------------------------------------- |
| `actions/tools/`          | Install CLI tools (terraform, kubectl, kind, trivy, yamllint) |
| `actions/checks/`         | Terraform fmt/validate, yamllint, Trivy IaC scan              |
| `actions/terraform-kind/` | kind cluster + Argo CD bootstrap (init, plan, apply, verify)  |
| `actions/terraform-eks/`  | EKS stub (not implemented yet)                                |

### CI Pipeline Flow (`ci.yaml`)

Runs on **self-hosted runner** (Docker on local machine):

1. **Checkout** — Fetch repository code
2. **Tools** — Install/verify required CLI tools
3. **Checks** — Terraform fmt/validate, yamllint, Trivy config scan
4. **Terraform Kind** — Deploy infrastructure:
   - Terraform init (with retry logic)
   - Terraform plan
   - Terraform apply (create kind cluster + Argo CD)
   - Verify cluster nodes ready
   - Verify Argo CD deployment and Applications

Cluster persists after workflow completes (no auto-destroy).

---

## Observability

### Alert Rules

| Rule            | Description                                         | Severity |
| --------------- | --------------------------------------------------- | -------- |
| `HighErrorRate` | >5% of HTTP requests return 5xx for 5 minutes       | critical |
| `HPAMaxedOut`   | HPA current replicas == max replicas for 15 minutes | warning  |

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

### `dev` (Active)

- **Cluster**: kind (1 control-plane + 2 workers)
- **State**: Local filesystem
- **Cache Images**: zot
- **GitOps**: Argo CD installed via Terraform Helm provider
- **CI/CD**: GitHub Actions (self-hosted runner)

### `aws` (Planned)

- **Cluster**: Amazon EKS
- **Networking**: VPC · subnets · security groups
- **IAM**: IRSA roles for service accounts
- **Storage**: S3 buckets · EBS CSI driver
- **Observability**: AMP (metrics) · AMG (Grafana)

---

## License

This project is open source and available under the [MIT License](LICENSE).
