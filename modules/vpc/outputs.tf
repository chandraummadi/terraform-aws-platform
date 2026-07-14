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

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the VPC. Null unless enable_ipv6 = true."
  value       = try(aws_vpc.this.ipv6_cidr_block, null)
}

output "vpc_secondary_cidr_blocks" {
  description = "Additional IPv4 CIDR blocks associated via secondary_cidr_blocks."
  value       = [for a in aws_vpc_ipv4_cidr_block_association.this : a.cidr_block]
}

output "default_security_group_id" {
  description = "ID of the VPC's default security group."
  value       = aws_vpc.this.default_security_group_id
}

output "default_network_acl_id" {
  description = "ID of the VPC's default network ACL."
  value       = aws_vpc.this.default_network_acl_id
}

output "default_route_table_id" {
  description = "ID of the VPC's default route table."
  value       = aws_vpc.this.default_route_table_id
}

output "availability_zones" {
  description = "Availability zones actually used by this VPC (explicit or auto-selected)."
  value       = local.azs
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway. Null when create_public_subnets = false."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "egress_only_internet_gateway_id" {
  description = "ID of the Egress-Only Internet Gateway. Null unless enable_ipv6 && create_egress_only_igw."
  value       = try(aws_egress_only_internet_gateway.this[0].id, null)
}

output "dhcp_options_id" {
  description = "ID of the custom DHCP Options Set. Null unless enable_dhcp_options = true."
  value       = try(aws_vpc_dhcp_options.this[0].id, null)
}

## --- Public tier -----------------------------------------------------------

output "public_subnet_ids" {
  description = "Map of availability zone => public subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "public_route_table_ids" {
  description = "Map of route-table key (AZ, or \"shared\") => public route table ID."
  value       = { for k, rt in aws_route_table.public : k => rt.id }
}

## --- Private tier -----------------------------------------------------------

output "private_subnet_ids" {
  description = "Map of availability zone => private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "private_route_table_ids" {
  description = "Map of availability zone => private route table ID."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

## --- Database tier -----------------------------------------------------------

output "database_subnet_ids" {
  description = "Map of availability zone => database subnet ID. Empty unless create_database_subnets = true."
  value       = { for az, s in aws_subnet.database : az => s.id }
}

output "database_subnet_group_name" {
  description = "Name of the DB subnet group. Null unless create_database_subnets && create_database_subnet_group."
  value       = try(aws_db_subnet_group.this[0].name, null)
}

output "database_route_table_ids" {
  description = "Map of route-table key => database route table ID. Empty unless create_database_subnets = true."
  value       = { for k, rt in aws_route_table.database : k => rt.id }
}

## --- ElastiCache tier -----------------------------------------------------------

output "elasticache_subnet_ids" {
  description = "Map of availability zone => ElastiCache subnet ID. Empty unless create_elasticache_subnets = true."
  value       = { for az, s in aws_subnet.elasticache : az => s.id }
}

output "elasticache_subnet_group_name" {
  description = "Name of the ElastiCache subnet group. Null unless create_elasticache_subnets && create_elasticache_subnet_group."
  value       = try(aws_elasticache_subnet_group.this[0].name, null)
}

## --- Redshift tier -----------------------------------------------------------

output "redshift_subnet_ids" {
  description = "Map of availability zone => Redshift subnet ID. Empty unless create_redshift_subnets = true."
  value       = { for az, s in aws_subnet.redshift : az => s.id }
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group. Null unless create_redshift_subnets && create_redshift_subnet_group."
  value       = try(aws_redshift_subnet_group.this[0].name, null)
}

## --- Intra tier -----------------------------------------------------------

output "intra_subnet_ids" {
  description = "Map of availability zone => intra subnet ID. Empty unless create_intra_subnets = true."
  value       = { for az, s in aws_subnet.intra : az => s.id }
}

output "intra_route_table_ids" {
  description = "Map of route-table key => intra route table ID. Empty unless create_intra_subnets = true."
  value       = { for k, rt in aws_route_table.intra : k => rt.id }
}

## --- Outpost tier -----------------------------------------------------------

output "outpost_subnet_ids" {
  description = "Map of synthetic index key => Outpost subnet ID. Empty unless create_outpost_subnets = true."
  value       = { for k, s in aws_subnet.outpost : k => s.id }
}

## --- NAT Gateway -----------------------------------------------------------

output "nat_gateway_ids" {
  description = "Map of availability zone => NAT Gateway ID. Empty map when nat_gateway_strategy = \"none\"."
  value       = { for az, ng in aws_nat_gateway.this : az => ng.id }
}

output "nat_gateway_public_ips" {
  description = "Map of availability zone => NAT Gateway Elastic IP. Only populated for AWS-allocated EIPs (empty when reuse_nat_ips = true — inspect external_nat_ip_ids yourself in that case)."
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

## --- Network ACLs -----------------------------------------------------------

output "public_network_acl_id" {
  description = "ID of the custom public NACL. Null unless manage_public_network_acl = true."
  value       = try(aws_network_acl.public[0].id, null)
}

output "private_network_acl_id" {
  description = "ID of the custom private NACL. Null unless manage_private_network_acl = true."
  value       = try(aws_network_acl.private[0].id, null)
}

output "database_network_acl_id" {
  description = "ID of the custom database NACL. Null unless manage_database_network_acl = true."
  value       = try(aws_network_acl.database[0].id, null)
}

output "elasticache_network_acl_id" {
  description = "ID of the custom ElastiCache NACL. Null unless manage_elasticache_network_acl = true."
  value       = try(aws_network_acl.elasticache[0].id, null)
}

output "intra_network_acl_id" {
  description = "ID of the custom intra NACL. Null unless manage_intra_network_acl = true."
  value       = try(aws_network_acl.intra[0].id, null)
}

## --- VPN / Customer Gateway -----------------------------------------------------------

output "vpn_gateway_id" {
  description = "ID of the VPN Gateway (created or attached-existing). Null unless enable_vpn_gateway or vpn_gateway_id is set."
  value       = local.has_vpn_gateway ? local.vpn_gateway_id : null
}

output "customer_gateway_ids" {
  description = "Map of logical name => Customer Gateway ID."
  value       = { for k, cgw in aws_customer_gateway.this : k => cgw.id }
}

## --- Flow Logs -----------------------------------------------------------

output "flow_log_id" {
  description = "ID of the VPC Flow Log. Null unless enable_flow_logs = true."
  value       = try(aws_flow_log.this[0].id, null)
}

output "flow_log_destination_arn" {
  description = "ARN flow logs are actually delivered to — either the self-contained Log Group this module created, or the bring-your-own destination you supplied."
  value       = try(local.flow_log_destination_arn, null)
}

output "flow_log_cloudwatch_log_group_name" {
  description = "Name of the self-contained CloudWatch Log Group. Null unless create_flow_log_cloudwatch_log_group = true (and destination_type = cloud-watch-logs)."
  value       = try(aws_cloudwatch_log_group.flow_log[0].name, null)
}

output "flow_log_iam_role_arn" {
  description = "ARN of the IAM role flow logs assume to publish. Either the self-contained role this module created, or the bring-your-own role you supplied."
  value       = try(local.flow_log_iam_role_arn, null)
}
