resource "tfe_notification_configuration" "aws_core_failure_notification" {
  for_each         = { for k, v in tfe_workspace.bootstrap_account : k => v if var.enable_aws_core_failure_notification }
  name             = "core_aws_failure_notification"
  enabled          = var.enable_aws_core_failure_notification
  destination_type = "email"
  triggers         = ["run:errored"]
  email_addresses  = var.notification_emails
  workspace_id     = each.value.id
}
