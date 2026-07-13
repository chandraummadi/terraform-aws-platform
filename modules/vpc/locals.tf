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

  # --- Subnet CIDRs --------------------------------------------------------
  # Auto-derivation carves /24s off var.cidr_block via cidrsubnet() (newbits
  # = 8). This assumes a parent block roomy enough for that (e.g. a /16);
  # if you're working with a smaller parent, pass explicit
  # public_subnet_cidrs/private_subnet_cidrs instead. Public subnets occupy
  # the first block of indices, private the next block, so growing one
  # tier's AZ count doesn't collide with the other tier's CIDRs.
  public_subnet_cidrs = var.create_public_subnets ? (
    length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
      for idx in range(length(local.azs)) : cidrsubnet(var.cidr_block, 8, idx)
    ]
  ) : []

  private_subnet_cidrs = var.create_private_subnets ? (
    length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
      for idx in range(length(local.azs)) : cidrsubnet(var.cidr_block, 8, idx + length(local.azs))
    ]
  ) : []

  public_subnets_by_az  = var.create_public_subnets ? zipmap(local.azs, local.public_subnet_cidrs) : {}
  private_subnets_by_az = var.create_private_subnets ? zipmap(local.azs, local.private_subnet_cidrs) : {}

  # --- NAT Gateway routing -------------------------------------------------
  # create_nat_gateway also requires both tiers to exist: NAT only makes
  # sense when there's a public subnet to host the gateway and a private
  # subnet that needs the route.
  create_nat_gateway = var.nat_gateway_strategy != "none" && var.create_public_subnets && var.create_private_subnets

  sorted_public_azs = sort(keys(local.public_subnets_by_az))
  first_public_az   = length(local.sorted_public_azs) > 0 ? local.sorted_public_azs[0] : null

  # AZs that actually get a real NAT Gateway resource.
  nat_azs = local.create_nat_gateway ? (
    var.nat_gateway_strategy == "single" ? (
      local.first_public_az == null ? {} : { (local.first_public_az) = local.public_subnets_by_az[local.first_public_az] }
    ) : local.public_subnets_by_az
  ) : {}

  # Map every private-subnet AZ to the NAT Gateway ID it should route
  # through. "single" -> every AZ points at the one NAT Gateway that exists.
  # "one_per_az" -> each AZ points at its own (keys match 1:1 since both
  # tiers are built from the same local.azs).
  nat_gateway_id_by_az = local.create_nat_gateway ? (
    var.nat_gateway_strategy == "single" ? {
      for az in keys(local.private_subnets_by_az) : az => values(aws_nat_gateway.this)[0].id
    } : { for az, ng in aws_nat_gateway.this : az => ng.id }
  ) : {}
}
