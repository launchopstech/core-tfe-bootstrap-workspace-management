output "instance_id" {
  description = "SSM bridge EC2 instance ID."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "SSM bridge security group ID."
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "SSM bridge EC2 IAM role name."
  value       = aws_iam_role.this.name
}
