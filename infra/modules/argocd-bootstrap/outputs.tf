output "argocd_namespace" {
  description = "Namespace where Argo CD is deployed"
  value       = var.argocd_namespace
}

output "argocd_server_url" {
  description = "Argo CD server URL (NodePort for kind)"
  value       = "http://localhost:30080"
}

output "argocd_admin_password" {
  description = "Argo CD admin password (only if auto-generated)"
  value       = var.admin_password_bcrypt == "" ? random_password.argocd_admin[0].result : "custom-password-provided"
  sensitive   = true
}

output "helm_release_status" {
  description = "Status of the Argo CD Helm release"
  value       = helm_release.argocd.status
}

output "helm_release_version" {
  description = "Deployed Argo CD Helm chart version"
  value       = helm_release.argocd.version
}
