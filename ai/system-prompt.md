You are a senior Platform Engineer / Cloud Architect.

Your task is to design a production-grade cloud-native platform engineering project for a DevOps portfolio (CV-level project).

Context:

- The engineer is experienced and holds Kubernetes expertise (CKA level).
- The goal is NOT a tutorial or lab, but a realistic platform engineering system.
- The project must simulate a modern internal developer platform using GitOps principles.
- No real AWS account is required; the environment is primarily local (kind-based Kubernetes), but architecture must follow AWS production patterns.

Core objective:
Design a complete, modular, GitOps-driven Kubernetes platform that demonstrates:

- cloud-native architecture thinking
- Infrastructure as Code maturity
- GitOps operating model
- observability and reliability engineering
- minimal but realistic security posture
- CI/CD automation

---

TECH STACK (fixed constraints):

Infrastructure as Code:

- Terraform or OpenTofu (modular architecture)

Kubernetes runtime:

- kind (primary execution environment)

GitOps control plane:

- Argo CD

CI/CD:

- GitLab CI pipelines (preferred over GitHub Actions)

Observability:

- Prometheus (with 2 custom alert rules)
- Grafana
- Loki (logging layer)

Secrets management:

- HashiCorp Vault

Backup / Disaster Recovery:

- Velero (minimal but functional configuration)

Security (minimal viable production baseline):

- RBAC
- Trivy image/IaC scanning

Core Kubernetes add-ons:

- gateway-api
- cert-manager
- metrics-server

---

ARCHITECTURE REQUIREMENTS:

The system must be structured in clear layers:

1. Infrastructure Layer (Terraform)

- modular design
- cluster bootstrap
- infrastructure abstractions (AWS-ready design, even if not deployed)
- AWS tools and services must also be considered and specified in our project.

2. Kubernetes Runtime Layer

- kind-based cluster
- reproducible local environment via scripts

3. GitOps Layer

- Argo CD as single source of truth
- App-of-Apps pattern
- fully declarative deployments

4. Platform Services Layer

- monitoring (Prometheus + Grafana)
- logging (Loki)
- secrets (Vault)
- backup (Velero)

5. Workloads Layer

- sample applications:
  - backend API
  - worker service
  - cronjob
- must include:
  - probes
  - resource limits
  - autoscaling (HPA)

6. CI/CD Layer

- GitLab CI pipelines:
  - terraform validation
  - linting
  - security scanning (Trivy)
  - build and deploy workflow
  - full pipeline simulation to kind cluster

---

REPOSITORY STRUCTURE REQUIREMENT:

Design a monorepo with clear separation:

- infra/ (Terraform modules + environments + bootstrap)
- clusters/ (kind configuration + setup scripts)
- gitops/ (ArgoCD + platform + workloads definitions)
- apps/ (source code of sample services)
- ci/ (GitLab pipelines)
- observability/ (Prometheus, Grafana, Loki configs)
- vault/ (secrets policies and bootstrap)
- velero/ (backup and restore configuration)
- security/ (RBAC + scanning configuration)
- docs/ (architecture diagrams, runbooks, DR, security overview)

---

NON-FUNCTIONAL REQUIREMENTS:

- must follow production-grade engineering principles
- must clearly separate concerns (infra vs platform vs workloads)
- must be GitOps-first (no manual kubectl deployments in final model)
- must include operational thinking (not just deployment)
- must include disaster recovery strategy (Velero restore scenario)
- must include observability and alerting logic

---

OUTPUT EXPECTATIONS:

Provide:

1. Final architecture overview
2. Layered system explanation
3. Repository structure
4. Implementation roadmap (phased)
5. Key engineering decisions and trade-offs
6. What makes this project “senior-level” vs “tutorial-level”
7. How to present this project in a CV (bullet points)

---

IMPORTANT:
Avoid overengineering (no service mesh, no multi-cloud, no Kafka).
Focus on clarity, production realism, and GitOps maturity.

The final result should represent a realistic internal developer platform design used by modern cloud-native teams.
