## ---------------------------------------------------------------------------
## VPC
## ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  instance_tenancy     = var.instance_tenancy
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

## ---------------------------------------------------------------------------
## Internet Gateway (only when public subnets exist)
## ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count = var.create_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

## ---------------------------------------------------------------------------
## Subnets
## ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = local.public_subnets_by_az

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets_by_az

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  # Private subnets never auto-assign public IPs, no variable escape hatch —
  # this is deliberate, not a placeholder.
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  })
}

## ---------------------------------------------------------------------------
## Public routing
## ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  count = var.create_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet_gateway" {
  count = var.create_public_subnets ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

## ---------------------------------------------------------------------------
## NAT Gateway — inline (not a child module; see README "NAT Gateway
## Scenarios" for the single / one_per_az / none tradeoffs). local.nat_azs
## is the set of AZs that actually get a NAT Gateway: all of them for
## one_per_az, just the first (alphabetically) for single, none for "none".
## ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = local.nat_azs

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

## ---------------------------------------------------------------------------
## Private routing — one route table per AZ so "one_per_az" NAT failover
## stays AZ-isolated; "single" strategy just points every table at the same
## (only) NAT Gateway (see local.nat_gateway_id_by_az).
## ---------------------------------------------------------------------------

resource "aws_route_table" "private" {
  for_each = local.private_subnets_by_az

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${each.key}"
  })
}

resource "aws_route" "private_nat_gateway" {
  for_each = local.create_nat_gateway ? local.private_subnets_by_az : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.nat_gateway_id_by_az[each.key]
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

## ---------------------------------------------------------------------------
## Network ACLs — inline, opt-in per tier. Secure-by-default: an
## aws_network_acl created with zero ingress/egress blocks gets AWS's
## standard custom-ACL behavior (implicit deny-all). There is no
## synthesized allow-all fallback here — traffic only flows once you supply
## explicit *_network_acl_ingress_rules / *_network_acl_egress_rules.
## ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  count = var.manage_public_network_acl && var.create_public_subnets ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  dynamic "ingress" {
    for_each = var.public_network_acl_ingress_rules
    content {
      rule_no    = ingress.value.rule_number
      protocol   = ingress.value.protocol
      action     = ingress.value.rule_action
      cidr_block = ingress.value.cidr_block
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
    }
  }

  dynamic "egress" {
    for_each = var.public_network_acl_egress_rules
    content {
      rule_no    = egress.value.rule_number
      protocol   = egress.value.protocol
      action     = egress.value.rule_action
      cidr_block = egress.value.cidr_block
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-nacl"
  })
}

resource "aws_network_acl" "private" {
  count = var.manage_private_network_acl && var.create_private_subnets ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  dynamic "ingress" {
    for_each = var.private_network_acl_ingress_rules
    content {
      rule_no    = ingress.value.rule_number
      protocol   = ingress.value.protocol
      action     = ingress.value.rule_action
      cidr_block = ingress.value.cidr_block
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
    }
  }

  dynamic "egress" {
    for_each = var.private_network_acl_egress_rules
    content {
      rule_no    = egress.value.rule_number
      protocol   = egress.value.protocol
      action     = egress.value.rule_action
      cidr_block = egress.value.cidr_block
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-nacl"
  })
}

## ---------------------------------------------------------------------------
## VPC Flow Logs (opt-in; destination owned by the caller — composability
## with the cloudwatch/s3/iam modules, not duplicated here)
## ---------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = var.flow_log_traffic_type
  log_destination      = var.flow_log_destination_arn
  log_destination_type = can(regex("^arn:aws[a-zA-Z-]*:logs:", var.flow_log_destination_arn)) ? "cloud-watch-logs" : "s3"
  iam_role_arn         = var.flow_log_iam_role_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}
