output "web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the WAFv2 Web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the WAFv2 Web ACL."
  value       = aws_wafv2_web_acl.this.name
}

output "web_acl_capacity" {
  description = "Calculated WCU capacity of the Web ACL."
  value       = aws_wafv2_web_acl.this.capacity
}

output "scope" {
  description = "Scope of the Web ACL."
  value       = aws_wafv2_web_acl.this.scope
}

output "log_group_name" {
  description = "CloudWatch Logs destination used for WAF logging."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the WAF log group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "attachment_mode" {
  description = "Whether the Web ACL expects target-owned or self-managed association."
  value       = local.normalized_attachment.mode
}
