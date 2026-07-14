# Changelog

All notable changes to this module are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to Semantic Versioning independent of every other
module in this repository (tag prefix `vpc/`, per `docs/coding-standards.md` §6).

## [Unreleased]

### Fixed

- **`manage_default_security_group` now defaults to `true`, not `false`**
  (checkov `CKV2_AWS_12`). AWS's own default security group allows all
  traffic between members and all egress — that's exactly the permissive
  default `docs/coding-standards.md` §5 prohibits, not an acceptable
  AWS-managed default to leave alone. Every other `manage_default_*`
  toggle in this module stays opt-in (least-surprise: don't touch what you
  didn't ask this module to manage) — this one toggle is the deliberate
  exception, because leaving it off by default meant every consumer using
  this module's defaults shipped with a real security gap. Not a breaking
  change note since no version has been tagged yet.
- The default-flip above didn't fully satisfy `CKV2_AWS_12` on its own:
  checkov statically parses `aws_default_security_group.this`'s
  `dynamic "ingress"`/`"egress"` blocks and can't execute their `for_each`
  to confirm the empty-list default resolves to zero rules (deny-all) at
  apply time, so it fails conservatively rather than assume emptiness.
  Added a documented `#checkov:skip=CKV2_AWS_12` on `aws_vpc.this`
  explaining the reasoning, per §5's "documented, justified exceptions"
  allowance — this rests on the AWS provider's documented
  `aws_default_security_group` semantics, not an observed `terraform
  apply` (no AWS account available per `docs/testing-strategy.md`).
- Added a documented `#checkov:skip=CKV2_AWS_19` on the NAT Gateway EIP —
  known checkov false positive (the check looks for EC2-instance
  attachment; a NAT Gateway attachment is the correct and only intended
  state for this EIP).

### Added

- Full feature-parity expansion (aligned with `terraform-aws-modules/terraform-aws-vpc`
  as the reference, adapted to this repo's `for_each`-over-`count` and
  typed-`object()` standards per `docs/coding-standards.md` §3/§9):
  - DHCP Options Set support.
  - Secondary IPv4 CIDR blocks and IPAM pool CIDR sourcing.
  - IPv6 dual-stack subnets, Egress-Only Internet Gateway, IPv6 default
    routes.
  - Five additional opt-in subnet tiers: `database`, `elasticache`,
    `redshift`, `intra` (zero egress, not even NAT), `outpost`. All default
    `false` — only `public`/`private` are on by default.
  - Subnet groups: `aws_db_subnet_group`, `aws_elasticache_subnet_group`,
    `aws_redshift_subnet_group`.
  - NAT Gateway EIP reuse (`reuse_nat_ips` / `external_nat_ip_ids`).
  - VPN Gateway + Customer Gateway + route propagation (public/private/intra).
  - Default VPC Security Group / Network ACL / Route Table management
    (opt-in, `false` by default — this module manages what it creates, not
    AWS's account-level defaults, unless asked).
  - VPC Block Public Access account/region control.
- **VPC Flow Logs redesigned to close a real tfsec finding**: previously
  required a caller-supplied destination ARN with no way to actually
  provision one, so `enable_flow_logs = true` on its own produced a flow
  log pointed at nothing verifiable. Now supports two modes:
  - Self-contained (default): module creates its own CloudWatch Log Group
    and a least-privilege IAM role/policy scoped to that one Log Group's
    ARN (never `Resource = "*"`, per §5).
  - Bring-your-own: `create_flow_log_cloudwatch_log_group = false` and/or
    `create_flow_log_cloudwatch_iam_role = false` with an existing
    `flow_log_destination_arn` / `flow_log_iam_role_arn` — e.g. to
    centralize flow logs from many VPCs into one Log Group owned by the
    `cloudwatch`/`iam` modules.
  - S3 destinations supported via `flow_log_destination_type = "s3"`
    (no IAM role needed for that path).
- NAT Gateway and Network ACL logic kept inline in `main.tf` rather than as
  child modules (see README design note) — neither is independently
  versioned or called directly by a consumer, so a submodule boundary adds
  indirection with no consumer-facing benefit.
- Per-AZ private route tables so `one_per_az` NAT failover stays
  AZ-isolated.
- `examples/basic`: two-AZ VPC with public/private subnets and a single NAT
  Gateway.
- Terratest suite (`tests/terratest/vpc_test.go`) applying `examples/basic`
  and asserting against live AWS state; gated behind `AWS_TESTS_ENABLED` in
  CI per `docs/testing-strategy.md`.
