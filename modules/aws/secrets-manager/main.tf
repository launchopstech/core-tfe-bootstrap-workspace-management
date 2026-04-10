locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })
}

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_definitions

  name                    = "${var.name_prefix}-${each.value.name_suffix}"
  description             = try(each.value.description, null)
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = try(each.value.recovery_window_in_days, 30)
  tags                    = merge(local.base_tags, try(each.value.tags, {}))
}

resource "aws_secretsmanager_secret_version" "initial" {
  for_each = {
    for k, v in var.secret_definitions : k => v
    if try(v.initial_value, null) != null
  }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value.initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

