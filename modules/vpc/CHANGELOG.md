# Changelog

All notable changes to this module are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to Semantic Versioning independent of every other
module in this repository (tag prefix `vpc/`, per `docs/coding-standards.md` §6).

## [Unreleased]

### Added

- Initial release of the `vpc` module (Sprint 2).
- VPC with configurable CIDR, DNS support/hostnames, instance tenancy.
- Public and private subnets across an auto-selected or explicit set of
  availability zones, with auto-derived or explicit CIDRs per tier.
- Internet Gateway + public route table (opt-out via `create_public_subnets`).
- NAT Gateway egress for private subnets, selectable via
  `nat_gateway_strategy` as `single` (cost-optimized), `one_per_az` (HA), or
  `none`.
- Per-AZ private route tables so `one_per_az` NAT failover stays AZ-isolated.
- Optional custom Network ACLs for public and/or private subnets —
  deny-by-default when enabled with no explicit rules (no implicit
  allow-all). Kept inline in `main.tf` rather than as a child module: NAT
  Gateway and NACL logic are never independently versioned or called
  directly by a consumer, so a submodule boundary would add indirection
  without adding any consumer-facing capability (see README design notes).
- Optional VPC Flow Logs to a caller-supplied destination (CloudWatch Log
  Group or S3), with no IAM role/log group created by this module
  (composability — that belongs to the `iam`/`cloudwatch` modules).
- `examples/basic`: two-AZ VPC with public/private subnets and a single NAT
  Gateway.
- Terratest suite (`tests/terratest/vpc_test.go`) applying `examples/basic`
  and asserting against live AWS state; gated behind `AWS_TESTS_ENABLED` in
  CI per `docs/testing-strategy.md`.
