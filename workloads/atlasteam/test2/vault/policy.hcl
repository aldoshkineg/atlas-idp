# Vault policy for test2 workload (group: atlasteam)
path "secret/workloads/atlasteam/test2/*" {
  capabilities = ["read", "list"]
}
