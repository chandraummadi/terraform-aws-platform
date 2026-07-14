locals {
  name_prefix = var.name

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "terraform-aws-platform/vpc"
  })

  # --- Availability zones -----------------------------------------------
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    sort(data.aws_availability_zones.available.names),
    0,
    min(var.availability_zone_count, length(data.aws_availability_zones.available.names)),
  )
  az_count = length(local.azs)

  # --- IPv4 subnet CIDR auto-derivation ------------------------------------
  # Every tier that supports auto-derivation gets a fixed index block of
  # width az_count, offset by tier position, so tiers can never collide
  # even if only some are enabled. Assumes a parent CIDR roomy enough for
  # /24s (e.g. a /16); pass explicit *_subnet_cidrs for smaller parents.
  tier_offset_public      = 0 * local.az_count
  tier_offset_private     = 1 * local.az_count
  tier_offset_database    = 2 * local.az_count
  tier_offset_elasticache = 3 * local.az_count
  tier_offset_redshift    = 4 * local.az_count
  tier_offset_intra       = 5 * local.az_count

  public_subnet_cidrs = var.create_public_subnets ? (
    length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_public + idx)]
  ) : []

  private_subnet_cidrs = var.create_private_subnets ? (
    length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_private + idx)]
  ) : []

  database_subnet_cidrs = var.create_database_subnets ? (
    length(var.database_subnet_cidrs) > 0 ? var.database_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_database + idx)]
  ) : []

  elasticache_subnet_cidrs = var.create_elasticache_subnets ? (
    length(var.elasticache_subnet_cidrs) > 0 ? var.elasticache_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_elasticache + idx)]
  ) : []

  redshift_subnet_cidrs = var.create_redshift_subnets ? (
    length(var.redshift_subnet_cidrs) > 0 ? var.redshift_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_redshift + idx)]
  ) : []

  intra_subnet_cidrs = var.create_intra_subnets ? (
    length(var.intra_subnet_cidrs) > 0 ? var.intra_subnet_cidrs :
    [for idx in range(local.az_count) : cidrsubnet(var.cidr_block, 8, local.tier_offset_intra + idx)]
  ) : []

  # --- IPv6 subnet CIDR auto-derivation (only when enable_ipv6) -----------
  # Same offset scheme, carved from the VPC's /56 via cidrsubnet (newbits =
  # 8 -> /64 per subnet, standard AWS subnet IPv6 size).
  public_subnet_ipv6_cidrs = var.enable_ipv6 && var.create_public_subnets ? [
    for idx in range(local.az_count) : cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, local.tier_offset_public + idx)
  ] : []

  private_subnet_ipv6_cidrs = var.enable_ipv6 && var.create_private_subnets ? [
    for idx in range(local.az_count) : cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, local.tier_offset_private + idx)
  ] : []

  # --- Subnet AZ maps -------------------------------------------------------
  public_subnets_by_az      = var.create_public_subnets ? zipmap(local.azs, local.public_subnet_cidrs) : {}
  private_subnets_by_az     = var.create_private_subnets ? zipmap(local.azs, local.private_subnet_cidrs) : {}
  database_subnets_by_az    = var.create_database_subnets ? zipmap(local.azs, local.database_subnet_cidrs) : {}
  elasticache_subnets_by_az = var.create_elasticache_subnets ? zipmap(local.azs, local.elasticache_subnet_cidrs) : {}
  redshift_subnets_by_az    = var.create_redshift_subnets ? zipmap(local.azs, local.redshift_subnet_cidrs) : {}
  intra_subnets_by_az       = var.create_intra_subnets ? zipmap(local.azs, local.intra_subnet_cidrs) : {}

  public_subnet_ipv6_by_az  = var.enable_ipv6 && var.create_public_subnets ? zipmap(local.azs, local.public_subnet_ipv6_cidrs) : {}
  private_subnet_ipv6_by_az = var.enable_ipv6 && var.create_private_subnets ? zipmap(local.azs, local.private_subnet_ipv6_cidrs) : {}

  # --- NAT Gateway routing -------------------------------------------------
  # NAT only makes sense with a public tier to host it and at least one
  # egress-needing private-style tier to route through it.
  create_nat_gateway = var.nat_gateway_strategy != "none" && var.create_public_subnets && (
    var.create_private_subnets || var.create_database_subnets || var.create_elasticache_subnets || var.create_redshift_subnets
  )

  sorted_public_azs = sort(keys(local.public_subnets_by_az))
  first_public_az   = length(local.sorted_public_azs) > 0 ? local.sorted_public_azs[0] : null

  # AZs that actually get a real NAT Gateway resource.
  nat_azs = local.create_nat_gateway ? (
    var.nat_gateway_strategy == "single" ? (
      local.first_public_az == null ? {} : { (local.first_public_az) = local.public_subnets_by_az[local.first_public_az] }
    ) : local.public_subnets_by_az
  ) : {}

  # Map every AZ in local.azs to the NAT Gateway ID any egress-needing tier
  # in that AZ should route through. "single" -> every AZ points at the one
  # NAT Gateway that exists. "one_per_az" -> each AZ points at its own.
  nat_gateway_id_by_az = local.create_nat_gateway ? (
    var.nat_gateway_strategy == "single" ? {
      for az in local.azs : az => values(aws_nat_gateway.this)[0].id
    } : { for az, ng in aws_nat_gateway.this : az => ng.id }
  ) : {}

  # --- VPN Gateway ID (created or attached-existing) -----------------------
  vpn_gateway_id  = try(aws_vpn_gateway.this[0].id, var.vpn_gateway_id)
  has_vpn_gateway = var.enable_vpn_gateway || var.vpn_gateway_id != null

  # --- Route table key sets (for_each-friendly single-vs-per-AZ toggle) ---
  # Tiers with a "create_multiple_*_route_tables" toggle get one route
  # table per AZ when true, or a single shared "shared" key when false.
  # Tiers without that toggle (database/elasticache/redshift) always get a
  # single shared table when the tier is enabled.
  public_route_table_keys = var.create_public_subnets ? (
    var.create_multiple_public_route_tables ? toset(keys(local.public_subnets_by_az)) : toset(["shared"])
  ) : toset([])

  intra_route_table_keys = var.create_intra_subnets ? (
    var.create_multiple_intra_route_tables ? toset(keys(local.intra_subnets_by_az)) : toset(["shared"])
  ) : toset([])

  database_route_table_keys    = var.create_database_subnets ? toset(["shared"]) : toset([])
  elasticache_route_table_keys = var.create_elasticache_subnets ? toset(["shared"]) : toset([])
  redshift_route_table_keys    = var.create_redshift_subnets ? toset(["shared"]) : toset([])

  # --- NAT Gateway allocation IDs, honoring reuse_nat_ips -------------------
  sorted_nat_azs          = sort(keys(local.nat_azs))
  nat_allocation_id_by_az = local.create_nat_gateway ? (
    var.reuse_nat_ips ? {
      for idx, az in local.sorted_nat_azs : az => var.external_nat_ip_ids[idx]
    } : { for az, eip in aws_eip.nat : az => eip.id }
  ) : {}

  # --- VPC Flow Logs --------------------------------------------------------
  # Self-contained-or-bring-your-own resolution: this module creates its own
  # Log Group/IAM role only when the corresponding create_flow_log_* toggle
  # is true AND destination_type is cloud-watch-logs (S3 destinations never
  # need a role, and bring-your-own callers set the toggle false).
  create_flow_log_cloudwatch_log_group = var.enable_flow_logs && var.flow_log_destination_type == "cloud-watch-logs" && var.create_flow_log_cloudwatch_log_group
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_logs && var.flow_log_destination_type == "cloud-watch-logs" && var.create_flow_log_cloudwatch_iam_role

  flow_log_cloudwatch_log_group_name_suffix = var.flow_log_cloudwatch_log_group_name_suffix == "" ? aws_vpc.this.id : var.flow_log_cloudwatch_log_group_name_suffix

  flow_log_destination_arn = local.create_flow_log_cloudwatch_log_group ? try(aws_cloudwatch_log_group.flow_log[0].arn, null) : var.flow_log_destination_arn
  flow_log_iam_role_arn    = local.create_flow_log_cloudwatch_iam_role ? try(aws_iam_role.vpc_flow_log_cloudwatch[0].arn, null) : var.flow_log_iam_role_arn

  # Scoped to exactly the one Log Group this module creates — never a
  # wildcard Resource, per docs/coding-standards.md §5.
  flow_log_group_arn = local.create_flow_log_cloudwatch_log_group ? (
    "arn:${data.aws_partition.current[0].partition}:logs:${data.aws_region.current[0].region}:${data.aws_caller_identity.current[0].account_id}:log-group:${aws_cloudwatch_log_group.flow_log[0].name}:*"
  ) : null
}
