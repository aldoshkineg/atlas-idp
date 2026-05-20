# AWS environment (stub)

AWS-ready layout for portfolio documentation. Not deployed without a real account.

Planned modules:

- `networking` — VPC, subnets, NAT
- `cluster` — EKS
- `iam` — IRSA roles for platform components
- `storage` — S3 for Velero, remote state
- `addons` — EBS CSI, load balancer controller
- `observability` — AMP / AMG integration stubs

Copy `local-kind` patterns and swap kind module for EKS when ready.
