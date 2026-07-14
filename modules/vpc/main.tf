## ---------------------------------------------------------------------------
## VPC
## ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_12: This VPC's default security group IS locked to deny-all by aws_default_security_group.this below (manage_default_security_group defaults to true; its dynamic ingress/egress blocks default to an empty for_each, which the AWS provider's documented behavior for this resource treats as "remove every rule not declared" — deny-all at apply time). checkov statically parses the dynamic block but cannot execute its for_each to confirm the empty-list default, so it fails conservatively rather than prove emptiness. Not independently verified against live AWS (no account available per docs/testing-strategy.md) — this reasoning rests on the AWS provider's documented aws_default_security_group semantics, not an observed apply.
  region = var.region

  cidr_block          = var.use_ipam_pool ? null : var.cidr_block
  ipv4_ipam_pool_id   = var.use_ipam_pool ? var.ipv4_ipam_pool_id : null
  ipv4_netmask_length = var.use_ipam_pool ? var.ipv4_netmask_length : null

  assign_generated_ipv6_cidr_block = var.enable_ipv6 && var.ipv6_ipam_pool_id == null ? true : null
  ipv6_ipam_pool_id                = var.ipv6_ipam_pool_id
  ipv6_netmask_length              = var.ipv6_ipam_pool_id != null ? var.ipv6_netmask_length : null

  instance_tenancy                     = var.instance_tenancy
  enable_dns_support                   = var.enable_dns_support
  enable_dns_hostnames                 = var.enable_dns_hostnames
  enable_network_address_usage_metrics = var.enable_network_address_usage_metrics

  tags = merge(local.common_tags, var.vpc_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  for_each = toset(var.secondary_cidr_blocks)

  region     = var.region
  vpc_id     = aws_vpc.this.id
  cidr_block = each.value
}

resource "aws_vpc_block_public_access_options" "this" {
  count = var.vpc_block_public_access_options != null ? 1 : 0

  region                      = var.region
  internet_gateway_block_mode = var.vpc_block_public_access_options.internet_gateway_block_mode
}

## ---------------------------------------------------------------------------
## DHCP Options Set
## ---------------------------------------------------------------------------

resource "aws_vpc_dhcp_options" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  region = var.region

  domain_name         = var.dhcp_options_domain_name
  domain_name_servers = var.dhcp_options_domain_name_servers
  ntp_servers         = var.dhcp_options_ntp_servers

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dhcp"
  })
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  region          = var.region
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

## ---------------------------------------------------------------------------
## Internet Gateway (only when public subnets exist)
## ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count = var.create_public_subnets ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_egress_only_internet_gateway" "this" {
  count = var.enable_ipv6 && var.create_egress_only_igw ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eigw"
  })
}

## ---------------------------------------------------------------------------
## Public subnets
## ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = local.public_subnets_by_az

  region = var.region

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = var.map_public_ip_on_launch

  assign_ipv6_address_on_creation = var.enable_ipv6
  ipv6_cidr_block                 = var.enable_ipv6 ? local.public_subnet_ipv6_by_az[each.key] : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  for_each = local.public_route_table_keys

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = each.key == "shared" ? "${local.name_prefix}-public-rt" : "${local.name_prefix}-public-rt-${each.key}"
  })
}

resource "aws_route" "public_internet_gateway" {
  for_each = local.public_route_table_keys

  region                 = var.region
  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_internet_gateway_ipv6" {
  for_each = var.enable_ipv6 ? local.public_route_table_keys : toset([])

  region                      = var.region
  route_table_id              = aws_route_table.public[each.key].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  region         = var.region
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[var.create_multiple_public_route_tables ? each.key : "shared"].id
}

## ---------------------------------------------------------------------------
## Private subnets
## ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = local.private_subnets_by_az

  region = var.region

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  # Private subnets never auto-assign a public IPv4 — deliberate, no
  # variable escape hatch.
  map_public_ip_on_launch = false

  assign_ipv6_address_on_creation = var.enable_ipv6
  ipv6_cidr_block                 = var.enable_ipv6 ? local.private_subnet_ipv6_by_az[each.key] : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  })
}

# One route table per AZ so "one_per_az" NAT failover stays AZ-isolated;
# "single" strategy just points every table at the same NAT Gateway (see
# local.nat_gateway_id_by_az).
resource "aws_route_table" "private" {
  for_each = local.private_subnets_by_az

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${each.key}"
  })
}

resource "aws_route" "private_nat_gateway" {
  for_each = local.create_nat_gateway ? local.private_subnets_by_az : {}

  region                 = var.region
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = local.nat_gateway_id_by_az[each.key]

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "private_ipv6_egress" {
  for_each = var.enable_ipv6 && var.create_egress_only_igw ? local.private_subnets_by_az : {}

  region                      = var.region
  route_table_id              = aws_route_table.private[each.key].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  region         = var.region
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

## ---------------------------------------------------------------------------
## Database subnets (opt-in)
## ---------------------------------------------------------------------------

resource "aws_subnet" "database" {
  for_each = local.database_subnets_by_az

  region = var.region

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-${each.key}"
    Tier = "database"
  })
}

resource "aws_db_subnet_group" "this" {
  count = var.create_database_subnets && var.create_database_subnet_group ? 1 : 0

  region      = var.region
  name        = lower(coalesce(var.database_subnet_group_name, local.name_prefix))
  description = "Database subnet group for ${local.name_prefix}"
  subnet_ids  = [for s in aws_subnet.database : s.id]

  tags = merge(local.common_tags, {
    Name = lower(coalesce(var.database_subnet_group_name, local.name_prefix))
  })
}

resource "aws_route_table" "database" {
  for_each = local.database_route_table_keys

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-rt"
  })
}

resource "aws_route" "database_internet_gateway" {
  for_each = var.create_database_subnets && var.create_database_internet_gateway_route ? local.database_route_table_keys : toset([])

  region                 = var.region
  route_table_id         = aws_route_table.database[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_nat_gateway" {
  for_each = (
    var.create_database_subnets && !var.create_database_internet_gateway_route &&
    var.create_database_nat_gateway_route && local.create_nat_gateway
  ) ? local.database_route_table_keys : toset([])

  region                 = var.region
  route_table_id         = aws_route_table.database[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  # A single shared database route table always exists when this tier is
  # enabled, so route through whichever NAT Gateway serves the first AZ.
  nat_gateway_id = local.nat_gateway_id_by_az[local.azs[0]]

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "database" {
  for_each = local.database_subnets_by_az

  region         = var.region
  subnet_id      = aws_subnet.database[each.key].id
  route_table_id = aws_route_table.database["shared"].id
}

## ---------------------------------------------------------------------------
## ElastiCache subnets (opt-in)
## ---------------------------------------------------------------------------

resource "aws_subnet" "elasticache" {
  for_each = local.elasticache_subnets_by_az

  region = var.region

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-elasticache-${each.key}"
    Tier = "elasticache"
  })
}

resource "aws_elasticache_subnet_group" "this" {
  count = var.create_elasticache_subnets && var.create_elasticache_subnet_group ? 1 : 0

  region      = var.region
  name        = coalesce(var.elasticache_subnet_group_name, local.name_prefix)
  description = "ElastiCache subnet group for ${local.name_prefix}"
  subnet_ids  = [for s in aws_subnet.elasticache : s.id]

  tags = merge(local.common_tags, {
    Name = coalesce(var.elasticache_subnet_group_name, local.name_prefix)
  })
}

resource "aws_route_table" "elasticache" {
  for_each = local.elasticache_route_table_keys

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-elasticache-rt"
  })
}

resource "aws_route" "elasticache_nat_gateway" {
  for_each = var.create_elasticache_subnets && local.create_nat_gateway ? local.elasticache_route_table_keys : toset([])

  region                 = var.region
  route_table_id         = aws_route_table.elasticache[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.nat_gateway_id_by_az[local.azs[0]]

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "elasticache" {
  for_each = local.elasticache_subnets_by_az

  region         = var.region
  subnet_id      = aws_subnet.elasticache[each.key].id
  route_table_id = aws_route_table.elasticache["shared"].id
}

## ---------------------------------------------------------------------------
## Redshift subnets (opt-in, niche)
## ---------------------------------------------------------------------------

resource "aws_subnet" "redshift" {
  for_each = local.redshift_subnets_by_az

  region = var.region

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-${each.key}"
    Tier = "redshift"
  })
}

resource "aws_redshift_subnet_group" "this" {
  count = var.create_redshift_subnets && var.create_redshift_subnet_group ? 1 : 0

  region      = var.region
  name        = lower(coalesce(var.redshift_subnet_group_name, local.name_prefix))
  description = "Redshift subnet group for ${local.name_prefix}"
  subnet_ids  = [for s in aws_subnet.redshift : s.id]

  tags = merge(local.common_tags, {
    Name = lower(coalesce(var.redshift_subnet_group_name, local.name_prefix))
  })
}

resource "aws_route_table" "redshift" {
  for_each = local.redshift_route_table_keys

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-rt"
  })
}

resource "aws_route_table_association" "redshift" {
  for_each = local.redshift_subnets_by_az

  region    = var.region
  subnet_id = aws_subnet.redshift[each.key].id
  route_table_id = var.enable_public_redshift ? (
    aws_route_table.public[var.create_multiple_public_route_tables ? each.key : "shared"].id
  ) : aws_route_table.redshift["shared"].id
}

## ---------------------------------------------------------------------------
## Intra subnets (opt-in): no route to NAT or IGW, ever
## ---------------------------------------------------------------------------

resource "aws_subnet" "intra" {
  for_each = local.intra_subnets_by_az

  region = var.region

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-intra-${each.key}"
    Tier = "intra"
  })
}

resource "aws_route_table" "intra" {
  for_each = local.intra_route_table_keys

  region = var.region
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = each.key == "shared" ? "${local.name_prefix}-intra-rt" : "${local.name_prefix}-intra-rt-${each.key}"
  })

  # Deliberately no aws_route resources ever created for this tier — that's
  # the entire point of "intra": zero route out of the VPC, not even NAT.
}

resource "aws_route_table_association" "intra" {
  for_each = aws_subnet.intra

  region         = var.region
  subnet_id      = each.value.id
  route_table_id = aws_route_table.intra[var.create_multiple_intra_route_tables ? each.key : "shared"].id
}

## ---------------------------------------------------------------------------
## Outpost subnets (opt-in, niche, single-AZ)
## ---------------------------------------------------------------------------

resource "aws_subnet" "outpost" {
  for_each = var.create_outpost_subnets ? { for idx, cidr in var.outpost_subnet_cidrs : "outpost-${idx}" => cidr } : {}

  region = var.region

  vpc_id                          = aws_vpc.this.id
  availability_zone               = var.outpost_az
  cidr_block                      = each.value
  outpost_arn                     = var.outpost_arn
  customer_owned_ipv4_pool        = var.customer_owned_ipv4_pool
  map_customer_owned_ip_on_launch = var.map_customer_owned_ip_on_launch

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-outpost-${each.key}"
    Tier = "outpost"
  })
}

resource "aws_route_table_association" "outpost" {
  for_each = aws_subnet.outpost

  region    = var.region
  subnet_id = each.value.id
  # Outposts route through whichever private route table exists for the
  # first AZ — Outpost subnets are single-AZ by definition (var.outpost_az).
  route_table_id = aws_route_table.private[local.azs[0]].id
}

## ---------------------------------------------------------------------------
## NAT Gateway
## ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  #checkov:skip=CKV2_AWS_19: This EIP attaches to a NAT Gateway (see aws_nat_gateway.this below), not an EC2 instance — checkov's instance-attachment check doesn't recognize NAT Gateway association as valid, but an EIP with no traffic path except through its NAT Gateway is the correct, intended state here, not an orphaned allocation.
  for_each = !var.reuse_nat_ips ? local.nat_azs : {}

  region = var.region
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_azs

  region        = var.region
  allocation_id = local.nat_allocation_id_by_az[each.key]
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

## ---------------------------------------------------------------------------
## Network ACLs — inline, opt-in per tier. Secure-by-default: an
## aws_network_acl created with zero ingress/egress blocks gets AWS's
## standard custom-ACL behavior (implicit deny-all). No synthesized
## allow-all fallback — traffic only flows once you supply explicit rules.
## ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  count = var.manage_public_network_acl && var.create_public_subnets ? 1 : 0

  region     = var.region
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  dynamic "ingress" {
    for_each = var.public_network_acl_ingress_rules
    content {
      rule_no         = ingress.value.rule_number
      protocol        = ingress.value.protocol
      action          = ingress.value.rule_action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.public_network_acl_egress_rules
    content {
      rule_no         = egress.value.rule_number
      protocol        = egress.value.protocol
      action          = egress.value.rule_action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-nacl" })
}

resource "aws_network_acl" "private" {
  count = var.manage_private_network_acl && var.create_private_subnets ? 1 : 0

  region     = var.region
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  dynamic "ingress" {
    for_each = var.private_network_acl_ingress_rules
    content {
      rule_no         = ingress.value.rule_number
      protocol        = ingress.value.protocol
      action          = ingress.value.rule_action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.private_network_acl_egress_rules
    content {
      rule_no         = egress.value.rule_number
      protocol        = egress.value.protocol
      action          = egress.value.rule_action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-nacl" })
}

resource "aws_network_acl" "database" {
  count = var.manage_database_network_acl && var.create_database_subnets ? 1 : 0

  region     = var.region
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.database : s.id]

  dynamic "ingress" {
    for_each = var.database_network_acl_ingress_rules
    content {
      rule_no         = ingress.value.rule_number
      protocol        = ingress.value.protocol
      action          = ingress.value.rule_action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.database_network_acl_egress_rules
    content {
      rule_no         = egress.value.rule_number
      protocol        = egress.value.protocol
      action          = egress.value.rule_action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-database-nacl" })
}

resource "aws_network_acl" "elasticache" {
  count = var.manage_elasticache_network_acl && var.create_elasticache_subnets ? 1 : 0

  region     = var.region
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.elasticache : s.id]

  dynamic "ingress" {
    for_each = var.elasticache_network_acl_ingress_rules
    content {
      rule_no         = ingress.value.rule_number
      protocol        = ingress.value.protocol
      action          = ingress.value.rule_action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.elasticache_network_acl_egress_rules
    content {
      rule_no         = egress.value.rule_number
      protocol        = egress.value.protocol
      action          = egress.value.rule_action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-elasticache-nacl" })
}

resource "aws_network_acl" "intra" {
  count = var.manage_intra_network_acl && var.create_intra_subnets ? 1 : 0

  region     = var.region
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.intra : s.id]

  dynamic "ingress" {
    for_each = var.intra_network_acl_ingress_rules
    content {
      rule_no         = ingress.value.rule_number
      protocol        = ingress.value.protocol
      action          = ingress.value.rule_action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.intra_network_acl_egress_rules
    content {
      rule_no         = egress.value.rule_number
      protocol        = egress.value.protocol
      action          = egress.value.rule_action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-intra-nacl" })
}

## ---------------------------------------------------------------------------
## VPN Gateway & Customer Gateways
## ---------------------------------------------------------------------------

resource "aws_vpn_gateway" "this" {
  count = var.enable_vpn_gateway ? 1 : 0

  region            = var.region
  vpc_id            = aws_vpc.this.id
  amazon_side_asn   = var.amazon_side_asn
  availability_zone = var.vpn_gateway_az

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vgw" })
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.enable_vpn_gateway == false && var.vpn_gateway_id != null ? 1 : 0

  region         = var.region
  vpc_id         = aws_vpc.this.id
  vpn_gateway_id = var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  for_each = local.has_vpn_gateway && var.propagate_public_route_tables_vgw ? local.public_route_table_keys : toset([])

  region         = var.region
  route_table_id = aws_route_table.public[each.key].id
  vpn_gateway_id = local.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "private" {
  for_each = local.has_vpn_gateway && var.propagate_private_route_tables_vgw ? local.private_subnets_by_az : {}

  region         = var.region
  route_table_id = aws_route_table.private[each.key].id
  vpn_gateway_id = local.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "intra" {
  for_each = local.has_vpn_gateway && var.propagate_intra_route_tables_vgw ? local.intra_route_table_keys : toset([])

  region         = var.region
  route_table_id = aws_route_table.intra[each.key].id
  vpn_gateway_id = local.vpn_gateway_id
}

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  region      = var.region
  bgp_asn     = each.value.bgp_asn
  ip_address  = each.value.ip_address
  device_name = each.value.device_name
  type        = "ipsec.1"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

## ---------------------------------------------------------------------------
## Default VPC / Security Group / NACL / Route Table management (opt-in)
## ---------------------------------------------------------------------------

resource "aws_default_security_group" "this" {
  count = var.manage_default_security_group ? 1 : 0

  region = var.region
  vpc_id = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      description     = ingress.value.description
      self            = ingress.value.self
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = ingress.value.security_groups
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      description     = egress.value.description
      self            = egress.value.self
      cidr_blocks     = egress.value.cidr_blocks
      security_groups = egress.value.security_groups
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-default-sg" })
}

resource "aws_default_network_acl" "this" {
  count = var.manage_default_network_acl ? 1 : 0

  region                 = var.region
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  # subnet_ids intentionally not set — see
  # https://github.com/terraform-aws-modules/terraform-aws-vpc/issues/736;
  # every subnet already has an explicit NACL association (or the AWS
  # default) via the per-tier resources above.
  subnet_ids = null

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      rule_no         = ingress.value.rule_no
      action          = ingress.value.action
      protocol        = ingress.value.protocol
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      rule_no         = egress.value.rule_no
      action          = egress.value.action
      protocol        = egress.value.protocol
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-default-nacl" })

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

resource "aws_default_route_table" "this" {
  count = var.manage_default_route_table ? 1 : 0

  region                 = var.region
  default_route_table_id = aws_vpc.this.default_route_table_id

  dynamic "route" {
    for_each = var.default_route_table_routes
    content {
      cidr_block      = route.value.cidr_block
      ipv6_cidr_block = route.value.ipv6_cidr_block

      egress_only_gateway_id    = route.value.egress_only_gateway_id
      gateway_id                = route.value.gateway_id
      nat_gateway_id            = route.value.nat_gateway_id
      transit_gateway_id        = route.value.transit_gateway_id
      vpc_endpoint_id           = route.value.vpc_endpoint_id
      vpc_peering_connection_id = route.value.vpc_peering_connection_id
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-default-rt" })
}

## ---------------------------------------------------------------------------
## VPC Flow Logs — self-contained by default (own Log Group + scoped IAM
## role), bring-your-own via create_flow_log_cloudwatch_* = false. See the
## variable comments above for the full mode matrix.
## ---------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  region = var.region

  vpc_id                     = aws_vpc.this.id
  traffic_type               = var.flow_log_traffic_type
  log_destination_type       = var.flow_log_destination_type
  log_destination            = local.flow_log_destination_arn
  log_format                 = var.flow_log_log_format
  iam_role_arn               = local.flow_log_iam_role_arn
  deliver_cross_account_role = var.flow_log_deliver_cross_account_role
  max_aggregation_interval   = var.flow_log_max_aggregation_interval

  dynamic "destination_options" {
    for_each = var.flow_log_destination_type == "s3" ? [true] : []
    content {
      file_format                = var.flow_log_file_format
      hive_compatible_partitions = var.flow_log_hive_compatible_partitions
      per_hour_partition         = var.flow_log_per_hour_partition
    }
  }

  tags = merge(local.common_tags, var.vpc_flow_log_tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = local.create_flow_log_cloudwatch_log_group ? 1 : 0

  region = var.region

  name              = "${var.flow_log_cloudwatch_log_group_name_prefix}${local.flow_log_cloudwatch_log_group_name_suffix}"
  retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  kms_key_id        = var.flow_log_cloudwatch_log_group_kms_key_id
  skip_destroy      = var.flow_log_cloudwatch_log_group_skip_destroy
  log_group_class   = var.flow_log_cloudwatch_log_group_class

  tags = merge(local.common_tags, var.vpc_flow_log_tags, {
    Name = "${local.name_prefix}-flow-log"
  })
}

data "aws_iam_policy_document" "flow_log_cloudwatch_assume_role" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  statement {
    sid     = "AWSVPCFlowLogsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    dynamic "condition" {
      for_each = var.flow_log_cloudwatch_iam_role_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }
}

resource "aws_iam_role" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  name        = var.vpc_flow_log_iam_role_use_name_prefix ? null : coalesce(var.vpc_flow_log_iam_role_name, "${local.name_prefix}-flow-log-role")
  name_prefix = var.vpc_flow_log_iam_role_use_name_prefix ? "${coalesce(var.vpc_flow_log_iam_role_name, "${local.name_prefix}-flow-log-role")}-" : null
  path        = var.vpc_flow_log_iam_role_path

  assume_role_policy   = data.aws_iam_policy_document.flow_log_cloudwatch_assume_role[0].json
  permissions_boundary = var.vpc_flow_log_permissions_boundary

  tags = merge(local.common_tags, var.vpc_flow_log_tags)
}

# Scoped to exactly this module's own Log Group ARN — never Resource = "*",
# per docs/coding-standards.md §5.
data "aws_iam_policy_document" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  statement {
    sid    = "AWSVPCFlowLogsPushToCloudWatch"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = [local.flow_log_group_arn]
  }
}

resource "aws_iam_policy" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  name        = var.vpc_flow_log_iam_policy_use_name_prefix ? null : coalesce(var.vpc_flow_log_iam_policy_name, "${local.name_prefix}-flow-log-policy")
  name_prefix = var.vpc_flow_log_iam_policy_use_name_prefix ? "${coalesce(var.vpc_flow_log_iam_policy_name, "${local.name_prefix}-flow-log-policy")}-" : null
  policy      = data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].json

  tags = merge(local.common_tags, var.vpc_flow_log_tags)
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  role       = aws_iam_role.vpc_flow_log_cloudwatch[0].name
  policy_arn = aws_iam_policy.vpc_flow_log_cloudwatch[0].arn
}
