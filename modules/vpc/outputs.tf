output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Primary IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "availability_zones" {
  description = "Availability zones actually used by this VPC (either var.availability_zones as passed, or the auto-selected list)."
  value       = local.azs
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway. Null when create_public_subnets = false."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "public_subnet_ids" {
  description = "Map of availability zone => public subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "Map of availability zone => private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "public_route_table_id" {
  description = "ID of the shared public route table. Null when create_public_subnets = false."
  value       = try(aws_route_table.public[0].id, null)
}

output "private_route_table_ids" {
  description = "Map of availability zone => private route table ID."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "nat_gateway_ids" {
  description = "Map of availability zone => NAT Gateway ID. Empty map when nat_gateway_strategy = \"none\"."
  value       = { for az, ng in aws_nat_gateway.this : az => ng.id }
}

output "nat_gateway_public_ips" {
  description = "Map of availability zone => NAT Gateway Elastic IP. Empty map when nat_gateway_strategy = \"none\"."
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

output "public_network_acl_id" {
  description = "ID of the custom public NACL. Null unless manage_public_network_acl = true."
  value       = try(aws_network_acl.public[0].id, null)
}

output "private_network_acl_id" {
  description = "ID of the custom private NACL. Null unless manage_private_network_acl = true."
  value       = try(aws_network_acl.private[0].id, null)
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log. Null unless enable_flow_logs = true."
  value       = try(aws_flow_log.this[0].id, null)
}
