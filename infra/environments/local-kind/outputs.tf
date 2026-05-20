output "cluster_name" {
  value = var.cluster_name
}

output "gitops_root_app" {
  description = "Path to root Application manifest"
  value       = "../../../gitops/bootstrap/root-app.yaml"
}

output "gitlab_runner_dir" {
  description = "Local GitLab Runner (Docker) configuration"
  value       = "${path.module}/gitlab-runner"
}
