# Vault policy for seal workload (group: atlas-team)
path "secret/workloads/atlas-team/seal/*" {
  capabilities = ["read", "list"]
}
