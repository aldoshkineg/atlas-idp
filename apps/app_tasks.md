# Test Assignment: Text-to-PDF Service on Kubernetes

## Objective

Develop and deploy a cloud-native application that converts user-submitted text into PDF documents.

The solution must be fully containerized and deployed into Kubernetes using GitOps practices.

---

## Functional Requirements

### Frontend

Provide a web interface allowing users to:

* Enter arbitrary text
* Submit conversion requests
* Track document generation status
* Download generated PDF files

### Backend API

Implement REST API endpoints:

| Method | Endpoint                 | Description                   |
| ------ | ------------------------ | ----------------------------- |
| POST   | /documents               | Create PDF generation request |
| GET    | /documents/{id}          | Get document status           |
| GET    | /documents/{id}/download | Download generated PDF        |

### PDF Generation

Backend must:

* Accept text payload
* Generate PDF document
* Upload generated PDF into object storage
* Store metadata in PostgreSQL

### PostgreSQL

Store:

* document id
* creation timestamp
* status
* object storage path
* file size

### Redis

Use Redis for:

* caching document status requests
* asynchronous task queue

### Object Storage

Use MinIO as S3-compatible storage.

Store generated PDF files in dedicated bucket.

---

## Non-Functional Requirements

### Kubernetes

Application must run inside Kubernetes.

Required resources:

* frontend deployment
* backend deployment
* redis
* postgresql
* minio
* ingress

### GitOps

Deploy all workloads using Argo CD.

Repository structure:

infrastructure/
applications/

All manifests must be declarative.

### Observability

Expose Prometheus metrics.

Provide Grafana dashboard showing:

* request rate
* response latency
* error rate
* queue depth

### Security

* Non-root containers
* Resource limits
* Liveness probes
* Readiness probes
* Secrets stored separately from application manifests

### CI/CD

Pipeline must:

* Build container image
* Run tests
* Push image
* Update deployment manifests

---

## Acceptance Criteria

* Application accessible via Ingress
* PDF generation works successfully
* Files stored in MinIO
* Metadata stored in PostgreSQL
* Redis used for queue and cache
* Argo CD manages deployment state
* Metrics visible in Prometheus
* Dashboard available in Grafana

---

## Bonus

* HorizontalPodAutoscaler
* NetworkPolicies
* External Secrets
* OpenTelemetry tracing
* Canary deployment using Argo Rollouts

