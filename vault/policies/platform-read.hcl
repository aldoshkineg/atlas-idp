# Read-only access to platform secrets path (dev)
path "secret/data/platform/*" {
  capabilities = ["read", "list"]
}
