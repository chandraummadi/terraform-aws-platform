# Basic security-group example

Creates a security group in a throwaway VPC, allowing HTTPS inbound from
anywhere and unrestricted outbound. Fully self-contained — no dependency on
this repo's `vpc` module. For a richer example demonstrating every
rule-source type and real composition with `vpc`, see
[`examples/complete`](../complete).

## Usage

```hcl
module "security_group" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/security-group?ref=security-group/v1.0.0"

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
}
```

```bash
terraform init
terraform apply
```

This is the exact configuration `tests/terratest/security_group_test.go`
applies — keep both in sync.
