# Vault policy for testapp workload (group: testgroup)
path "secret/workloads/testgroup/testapp/*" {
  capabilities = ["read", "list"]
}
