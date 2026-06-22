# Vault policy for Seal workload (group: aldoshkineg)
path "secret/workloads/aldoshkineg/seal/*" {
  capabilities = ["read", "list"]
}
