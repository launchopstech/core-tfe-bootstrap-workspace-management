resource "tfe_notification_configuration" "aws_core_failure_notification" {
  for_each = var.enable_aws_core_failure_notification ? toset(["true"]) : toset([])
  name     = "core_aws_failure_notification"
  enabled  = var.enable_aws_core_failure_notification
  destination_type = "email"
  triggers = ["run:errored"]
  email_addresses = ["bomatra@gmail.com"]
  workspace_id = each.value.id
}