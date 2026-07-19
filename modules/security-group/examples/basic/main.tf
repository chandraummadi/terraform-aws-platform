# Basic example: a security group in its own throwaway VPC, allowing HTTPS
# inbound from anywhere and unrestricted outbound. Self-contained (creates
# its own aws_vpc rather than depending on the vpc module) so this example
# has no cross-module version-pinning to manage. For a richer example that
# demonstrates every rule-source type and uses this repo's own vpc module,
# see examples/complete.
#
# This is the exact configuration tests/terratest/security_group_test.go
# applies — keep the two in sync.

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

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_12: This is a minimal, throwaway VPC that exists only to give this example's security group something to attach to — it is NOT a demonstration of this repo's VPC best practices. For a production VPC with a locked-down default security group (and everything else in docs/coding-standards.md), use the modules/vpc module, which sets manage_default_security_group = true by default for exactly this reason. Duplicating that logic inline here would make this example a second, drifting copy of modules/vpc instead of a focused security-group example.
  #checkov:skip=CKV2_AWS_11: Same reasoning as CKV2_AWS_12 above — this VPC is a throwaway fixture, not a reference for how to configure a production VPC. modules/vpc supports enable_flow_logs (self-contained CloudWatch Log Group + scoped IAM role by default) for that purpose.
  cidr_block = "10.40.0.0/16"

  tags = {
    Name = "sg-example-basic-vpc"
  }
}

module "security_group" {
  source = "../../"

  name        = "sg-example-basic"
  environment = "dev"
  vpc_id      = aws_vpc.this.id

  ingress_rules = {
    https = {
      description = "HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  egress_rules = {
    all_outbound = {
      description = "Allow all outbound"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra-examples"
  }
}
