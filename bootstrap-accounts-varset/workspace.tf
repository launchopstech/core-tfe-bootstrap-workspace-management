#  enable this if tfe_variable_set.bootstap_accounts g;obal attribute is set false
data "tfe_workspace_ids" "bootstap_workspace" {
  organization = "core-aws"
  tag_names    = ["bootstrap"]
  exclude_tags = ["auto-generated-for-users"]
}
