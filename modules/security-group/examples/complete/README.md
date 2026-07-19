# Complete security-group example

Demonstrates every rule-source type this module supports, `vpc_associations`
across a secondary VPC, and custom `timeouts`. Uses this repo's own `vpc`
module (relative path) to provision the underlying network, rather than a
bare inline `aws_vpc` — see [`examples/basic`](../basic) for a minimal,
fully self-contained alternative with no cross-module dependency.

## What this demonstrates

- `cidr_ipv4` — HTTPS from the VPC CIDR
- `cidr_ipv6` — HTTP from an IPv6 range
- `self = true` — all protocols from other members of the same security
  group (a typed field, not a magic `"self"` string)
- `referenced_security_group_id` — MySQL from a separate, stand-in security
  group
- `prefix_list_id` — DNS from a managed prefix list
- Single-port shorthand — `to_port` defaults to `from_port` when omitted
- `vpc_associations` — this security group's rules also apply to a second
  VPC, without a second module call
- `timeouts` — custom create/delete timeouts

## Usage

```bash
terraform init
terraform apply
```

This is the exact configuration `tests/terratest/security_group_complete_test.go`
applies — keep both in sync.
