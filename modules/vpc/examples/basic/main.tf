# Basic example: a two-AZ VPC with public + private subnets and a single
# (cost-optimized) NAT Gateway. This is the configuration Terratest applies
# in tests/terratest/vpc_test.go — keep the two in sync.

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

module "vpc" {
  source = "../../"

  name        = "vpc-example-basic"
  environment = "dev"
  cidr_block  = "10.30.0.0/16"

  availability_zone_count = 2
  nat_gateway_strategy    = "single"

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra-examples"
  }
}
