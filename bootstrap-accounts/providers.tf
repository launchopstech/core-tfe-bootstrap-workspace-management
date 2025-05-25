provider "vault" {
  alias = "infra-prod"
  address = "http://localhost:8200"
  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = var.vault_approle_role_id
      secret_id = var.vault_approle_secret_id
    }
  }
}