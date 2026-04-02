output "hosted_zone_id" {
  description = "Route53 hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "Hosted zone name."
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Delegation name servers assigned by Route53."
  value       = aws_route53_zone.this.name_servers
}
