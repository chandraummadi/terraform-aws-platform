# Complete example: demonstrates every rule-source type this module
# supports (CIDR, IPv6 CIDR, self-reference, another security group,
# managed prefix list, single-port shorthand), vpc_associations across a
# secondary VPC, and custom timeouts.
#
# Uses this repo's own vpc module (relative path — same monorepo, both
# already independently tagged) rather than a bare inline aws_vpc, so this
# example also demonstrates real composition and inherits vpc's
# secure-by-default posture (locked-down default SG, opt-in flow logs)
# instead of re-implementing a fraction of it inline. See examples/basic
# for a minimal, fully self-contained alternative with no cross-module
# dependency.

terraform {
  required_version = ">= 1.15.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.50"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name           = "sg-example-complete"
  vpc_cidr       = "10.50.0.0/16"
  secondary_cidr = "10.51.0.0/16"

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra-examples"
  }
}

## ---------------------------------------------------------------------------
## Supporting resources (this repo's own vpc module + stand-ins for the
## referenced-security-group and prefix-list rule sources below)
## ---------------------------------------------------------------------------

module "vpc" {
  source = "../../../vpc"

  name        = local.name
  environment = "dev"
  cidr_block  = local.vpc_cidr

  availability_zone_count = 2
  nat_gateway_strategy    = "none" # no NAT needed for this example

  tags = local.tags
}

module "vpc_secondary" {
  source = "../../../vpc"

  name        = "${local.name}-secondary"
  environment = "dev"
  cidr_block  = local.secondary_cidr

  availability_zone_count = 2
  nat_gateway_strategy    = "none"

  tags = local.tags
}

# Stand-in "application" security group, used below purely as the source
# for a referenced_security_group_id rule — not created by this module.
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Stand-in application SG used as a referenced traffic source"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_ec2_managed_prefix_list" "dns" {
  name           = "${local.name}-dns"
  address_family = "IPv4"
  max_entries    = 1

  entry {
    cidr        = local.vpc_cidr
    description = "VPC CIDR"
  }

  tags = local.tags
}

## ---------------------------------------------------------------------------
## Security Group
## ---------------------------------------------------------------------------

module "security_group" {
  source = "../../"

  name        = local.name
  environment = "dev"
  description = "Complete security-group example — every rule-source type"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    https_from_vpc = {
      description = "HTTPS from the VPC CIDR"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
    }

    http_from_ipv6 = {
      description = "HTTP from an IPv6 range"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv6   = "2001:db8::/64" # documentation range (RFC 3849), not a real prefix
    }

    all_from_self = {
      description = "All protocols from members of this same security group"
      ip_protocol = "-1"
      self        = true # typed field — no "self" magic-string sentinel, per docs/coding-standards.md §3
    }

    mysql_from_app = {
      description                  = "MySQL from the stand-in app security group"
      from_port                    = 3306
      to_port                      = 3306
      ip_protocol                  = "tcp"
      referenced_security_group_id = aws_security_group.app.id
    }

    dns_from_prefix_list = {
      description    = "DNS from a managed prefix list"
      from_port      = 53
      to_port        = 53
      ip_protocol    = "udp"
      prefix_list_id = aws_ec2_managed_prefix_list.dns.id
    }

    single_port_shorthand = {
      description = "Single-port shorthand — to_port defaults to from_port when omitted"
      from_port   = 8080
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
    }

    ephemeral_from_vpc = {
      description = "Ephemeral port range from the VPC CIDR"
      from_port   = 32768
      to_port     = 60999
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
      tags = {
        Tier = "private"
      }
    }
  }

  egress_rules = {
    all_outbound = {
      description = "Allow all outbound"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # Share this same security group's rules with the secondary VPC instead
  # of duplicating the module call.
  vpc_associations = {
    secondary = {
      vpc_id = module.vpc_secondary.vpc_id
    }
  }

  timeouts = {
    create = "5m"
    delete = "10m"
  }

  tags = local.tags
}
