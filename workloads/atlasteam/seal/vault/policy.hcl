# Vault policy for seal workload (group: atlasteam)
path "secret/workloads/atlasteam/seal/*" {
  capabilities = ["read", "list"]
}
