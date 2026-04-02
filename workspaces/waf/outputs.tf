output "web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL."
  value       = module.web_acl.web_acl_arn
}

output "web_acl_id" {
  description = "ID of the WAFv2 Web ACL."
  value       = module.web_acl.web_acl_id
}

output "web_acl_name" {
  description = "Name of the WAFv2 Web ACL."
  value       = module.web_acl.web_acl_name
}

output "web_acl_capacity" {
  description = "Calculated WCU capacity of the Web ACL."
  value       = module.web_acl.web_acl_capacity
}

output "scope" {
  description = "Scope of the Web ACL."
  value       = module.web_acl.scope
}

output "log_group_name" {
  description = "Name of the CloudWatch Logs destination used for WAF logging."
  value       = module.web_acl.log_group_name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Logs destination used for WAF logging."
  value       = module.web_acl.log_group_arn
}

output "attachment_mode" {
  description = "Whether the Web ACL expects target-owned or self-managed association."
  value       = module.web_acl.attachment_mode
}
