# Basic VPC example

Creates a two-AZ VPC (`10.30.0.0/16`) with public + private subnets in each
AZ and a single shared NAT Gateway for private-subnet egress.

## Usage

```hcl
module "vpc" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/vpc?ref=vpc/v1.0.0"

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
```

```bash
terraform init
terraform apply
```

This is the exact configuration `tests/terratest/vpc_test.go` applies —
keep both in sync when changing either.
