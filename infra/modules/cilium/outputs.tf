output "cilium_installed" {
  description = "True if Cilium Helm release was created"
  value       = helm_release.cilium.status == "deployed"
}
