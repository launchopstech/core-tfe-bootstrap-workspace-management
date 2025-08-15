# 🚀 Terraform Bootstrap Project - Quick Start Guide

This guide helps you quickly resume work on the Terraform Cloud bootstrap workspace management project after a gap.

## 📋 Pre-Work Checklist

### 1. **Always Do Terraform Login First**
```bash
terraform login
```
- This opens your browser to generate/refresh your API token
- Ensures you have valid authentication to Terraform Cloud
- Required before running any Terraform commands

### 2. **Start OpenBao in Dev Mode**
```bash
openbao server -dev -dev-root-token-id="dev-only-token"
```
- **Important:** Dev mode data is NOT persistent
- All configuration is lost when OpenBao restarts
- Note the root token from startup logs (usually `dev-only-token`)

### 3. **Set Environment Variables**
```bash
export BAO_ADDR='http://127.0.0.1:8200'
export BAO_TOKEN='dev-only-token'  # Use actual token from startup
```

### 4. **Recreate OpenBao Configuration** (If OpenBao Restarted)
```bash
# Enable AppRole auth
bao auth enable -path=approle_dev approle

# Create policy
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

# Create AppRole
bao write auth/approle_dev/role/my-app-role \
  token_policies="terraform-policy" \
  token_ttl=1h \
  token_max_ttl=4h

# Get fresh credentials
bao read auth/approle_dev/role/my-app-role/role-id
bao write -f auth/approle_dev/role/my-app-role/secret-id
```

### 5. **Fix terraform.tfvars Variable Names**
**Critical:** Ensure variable names are lowercase:
```hcl
tfe_token              = "your-token-from-terraform-login"
vault_approle_role_id  = "role-id-from-openbao"
vault_approle_secret_id = "secret-id-from-openbao"
```
**NOT:** `TFE_TOKEN` (uppercase) - this won't work!

## 🏗️ Project Structure

```
core-tfe-bootstrap-workspace-management/
├── bootstrap-accounts/          # Main Terraform module
├── bootstrap-accounts-dev/      # Dev environment implementation
├── bootstrap-accounts-workbench/ # Workbench environment implementation
├── bootstrap-accounts-varset/   # Variable set management
├── policy.hcl                  # OpenBao policy file
├── OpenBao-Setup-Guide.md      # Detailed OpenBao setup
└── Terraform-Quick-Start.md    # This guide
```

## 🎯 Working Environments

Choose which environment you want to work on:

### **For Development Environment:**
```bash
cd bootstrap-accounts-dev
terraform init
terraform plan
terraform apply
```

### **For Workbench Environment:**
```bash
cd bootstrap-accounts-workbench  
terraform init
terraform plan
terraform apply
```

### **For Variable Sets:**
```bash
cd bootstrap-accounts-varset
terraform init
terraform plan
terraform apply
```

## ✅ Test Before Running Terraform

### **Test OpenBao Authentication:**
```bash
curl --request POST \
  --data '{"role_id":"YOUR_ROLE_ID","secret_id":"YOUR_SECRET_ID"}' \
  http://localhost:8200/v1/auth/approle_dev/login
```
Should return JSON with `client_token` field.

### **Test Terraform Cloud Access:**
```bash
curl -H "Authorization: Bearer YOUR_TFE_TOKEN" \
  https://app.terraform.io/api/v2/organizations/core-aws
```
Should return organization details.

## 🚨 Common Issues

| Issue | Solution |
|-------|----------|
| `TFE_TOKEN` not recognized | Change to `tfe_token` (lowercase) |
| "unauthorized" errors | Run `terraform login` again |
| "permission denied" on OpenBao | Recreate AppRole configuration |
| "invalid role or secret ID" | Generate fresh OpenBao credentials |
| "connection refused" to OpenBao | Start OpenBao server |

## 📝 What This Project Does

This system automates the creation of Terraform Cloud workspaces for AWS account bootstrapping:

1. **Creates TFE workspaces** for each AWS account
2. **Stores workspace metadata** in OpenBao
3. **Configures notifications** for workspace failures
4. **Manages variable sets** across environments
5. **Integrates with GitHub** for VCS-driven workflows

## 🔄 Typical Workflow

1. **Start OpenBao** and recreate configuration (if needed)
2. **Run terraform login** for fresh TFC authentication
3. **Update terraform.tfvars** with fresh credentials
4. **Choose environment** (dev, workbench, varset)
5. **Run terraform plan** to see changes
6. **Run terraform apply** to create resources

---

## 📚 Additional Resources

- [OpenBao-Setup-Guide.md](./OpenBao-Setup-Guide.md) - Detailed OpenBao configuration
- [Terraform Cloud Docs](https://developer.hashicorp.com/terraform/cloud-docs)
- [OpenBao Documentation](https://openbao.dev/docs/)

---

**Remember:** Always start with `terraform login` and ensure OpenBao is running! 🚀
