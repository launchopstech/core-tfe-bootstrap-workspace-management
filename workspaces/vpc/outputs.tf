output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }
output "private_subnet_cidrs" { value = var.private_subnets }
output "public_subnet_ids" { value = module.vpc.public_subnet_ids }
output "database_subnet_ids" { value = module.vpc.database_subnet_ids }
output "database_subnet_group_name" { value = module.vpc.database_subnet_group_name }
output "vpc_cidr_block" { value = module.vpc.vpc_cidr_block }
