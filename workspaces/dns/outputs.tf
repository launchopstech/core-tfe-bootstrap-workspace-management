output "hosted_zone_id" {
  description = "Route53 hosted zone ID."
  value       = module.public_zone.hosted_zone_id
}

output "zone_name" {
  description = "Hosted zone name."
  value       = module.public_zone.zone_name
}

output "name_servers" {
  description = "Delegation name servers assigned by Route53."
  value       = module.public_zone.name_servers
}
