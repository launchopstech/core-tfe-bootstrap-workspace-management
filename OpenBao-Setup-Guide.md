# OpenBao Setup Guide for Terraform Bootstrap Project

Deprecated as of the HCP Terraform Phase 1 refactor.

The active control-plane workflow no longer uses OpenBao or Vault. Keep this document only as historical reference for the pre-HCP-Terraform implementation.

This guide documents the step-by-step process to successfully set up OpenBao for the Terraform Cloud bootstrap workspace management system.

## 📋 Prerequisites

- OpenBao installed via Homebrew
- Terminal access with zsh shell
- Git repository initialized

## 🚀 Step 1: Start OpenBao in Dev Mode

```bash
openbao server -dev -dev-root-token-id="dev-only-token"
```

**Important Notes:**
- OpenBao will run on `http://127.0.0.1:8200`
- Root token will be `dev-only-token`
- Dev mode data is **not persistent** - all configuration is lost on restart

## 🔧 Step 2: Set Environment Variables

```bash
export BAO_ADDR='http://127.0.0.1:8200'
export BAO_TOKEN='dev-only-token'
```

## 🛡️ Step 3: Enable AppRole Authentication

```bash
bao auth enable -path=approle_dev approle
```

This creates the AppRole auth method at the custom path `approle_dev/` to match our Terraform configuration.

## 📜 Step 4: Create Terraform Policy

```bash
bao policy write terraform-policy - <<EOF
path "auth/approle_dev/login" {
  capabilities = ["create", "read"]
}
path "cloud/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/token/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

This policy allows:
- AppRole authentication at the custom path
- Full access to cloud metadata secrets
- Token creation and management

## 👤 Step 5: Create AppRole

```bash
bao write auth/approle_dev/role/my-app-role \
  token_policies="terraform-policy" \
  token_ttl=1h \
  token_max_ttl=4h
```

## 🔑 Step 6: Generate Credentials

### Get Role ID:
```bash
bao read auth/approle_dev/role/my-app-role/role-id
```

### Generate Secret ID:
```bash
bao write -f auth/approle_dev/role/my-app-role/secret-id
```

**Example Output:**
```
Role ID: 4c1b5cf9-1d82-e3e7-3b15-c0d319a9eeb6
Secret ID: 95a611af-32e6-82df-ac31-e92b470fc73a
```

## ⚙️ Step 7: Configure terraform.tfvars

**Critical:** Variable names must be lowercase for Terraform to recognize them.

```hcl
tfe_token              = "your-terraform-cloud-token"
vault_approle_role_id  = "4c1b5cf9-1d82-e3e7-3b15-c0d319a9eeb6"
vault_approle_secret_id = "95a611af-32e6-82df-ac31-e92b470fc73a"
aws_core_oauth_token_id = "value"
enable_aws_core_failure_notification = false
terraform_version        = "~> 1.0.0"
tfe_prod_admin_token     = "your-terraform-cloud-token"
```

## ✅ Step 8: Test OpenBao Authentication

```bash
curl --request POST \
  --data '{"role_id":"4c1b5cf9-1d82-e3e7-3b15-c0d319a9eeb6","secret_id":"95a611af-32e6-82df-ac31-e92b470fc73a"}' \
  http://localhost:8200/v1/auth/approle_dev/login
```

**Expected Response:**
```json
{
  "auth": {
    "client_token": "s.xxxxxxxxxxxxxxxx",
    "accessor": "xxxxxxxxxxxxxxxx",
    ...
  }
}
```

## 🏃‍♂️ Step 9: Run Terraform

```bash
cd bootstrap-accounts-workbench
terraform init
terraform plan
```

## 🔄 If OpenBao Restarts

**Remember:** Dev mode doesn't persist data. If OpenBao restarts, you must:

1. Note the new root token from startup logs
2. Repeat steps 2-6 with the new token
3. Update terraform.tfvars with new credentials

## 🚨 Common Issues & Solutions

### Issue: "TFE_TOKEN" not recognized
**Solution:** Change `TFE_TOKEN` to `tfe_token` (lowercase)

### Issue: "permission denied" on AppRole login
**Solution:** Verify policy is correctly attached to the role

### Issue: "invalid role or secret ID"
**Solution:** Regenerate credentials after OpenBao restart

### Issue: "http: server gave HTTP response to HTTPS client"
**Solution:** Use `http://` not `https://` in addresses

## 📁 Project Structure

```
core-tfe-bootstrap-workspace-management/
├── bootstrap-accounts/          # Terraform module
├── bootstrap-accounts-dev/      # Dev environment
├── bootstrap-accounts-workbench/ # Workbench environment
├── bootstrap-accounts-varset/   # Variable sets
├── policy.hcl                  # Vault policy file
└── OpenBao-Setup-Guide.md      # This guide
```

## 🎯 What This Setup Achieves

- **Secure Authentication:** AppRole-based auth for Terraform
- **Secret Management:** Store workspace metadata in OpenBao
- **Environment Isolation:** Separate workspaces for dev/prod
- **Automated Bootstrapping:** Create TFE workspaces for AWS accounts

---

**Success Criteria:** When `terraform plan` runs without authentication errors, your OpenBao setup is complete! 🎉
