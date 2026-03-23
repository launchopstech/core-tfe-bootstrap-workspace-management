path "auth/approle_dev/login" {
  capabilities = ["create", "read"]
}
path "cloud/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/token/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}