# Changelog

All notable changes to this module are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to Semantic Versioning independent of every other
module in this repository (tag prefix `security-group/`, per
`docs/coding-standards.md` §6).

## [Unreleased]

### Fixed

- Added a documented `#checkov:skip=CKV2_AWS_5` on `aws_security_group.this`.
  This module produces a standalone security group by design (per this
  repo's composable-not-monolithic principle) — attachment to an instance,
  ENI, ALB, or Lambda happens in a consuming module, not here, so any
  isolated invocation of this module (including `examples/basic`) will
  always look "unattached" to a same-module static scan.
- Added documented `#checkov:skip=CKV2_AWS_12` / `CKV2_AWS_11` on the
  throwaway `aws_vpc` resource inside `examples/basic/main.tf`. That VPC
  exists only to give the example's security group something to attach to
  — it's deliberately not built via the `vpc` module (to avoid cross-module
  version coupling in the example), so it doesn't inherit `vpc`'s
  locked-down-default-SG / flow-log defaults. Production consumers should
  use `modules/vpc`, which already handles both correctly.

### Added

- Initial release of the `security-group` module (Sprint 3).
- Single security group per module call, with ingress/egress rules
  declared as `map(object({...}))` — each rule keyed by a logical name you
  choose, which also becomes that rule's `Name` tag.
- Ingress/egress rules implemented as standalone
  `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule`
  resources rather than inline `ingress {}` / `egress {}` blocks on
  `aws_security_group` — adding or removing one rule never forces
  replacement of the security group or any other rule. Matches the design
  `terraform-aws-modules/terraform-aws-security-group` v6.0.0 (released
  June 2026) moved to for the same reason.
- Each rule requires exactly one traffic source: `cidr_ipv4`, `cidr_ipv6`,
  `prefix_list_id`, `referenced_security_group_id`, or `self = true` — a
  typed boolean field, not a magic `"self"` string sentinel, per
  `docs/coding-standards.md` §3.
- Secure by default: `ingress_rules`/`egress_rules` both default to `{}` —
  this module never opens a port on its own.
- `enable_exclusive_rules` defaults to `true`: Terraform enforces that only
  the rules declared in this module's config exist on the security group,
  reverting any rule added out-of-band (console, CLI, another Terraform
  config) on the next apply. Deliberately strict/drift-correcting rather
  than permissive — set `false` only with a documented reason for letting
  this security group coexist with externally managed rules.
- No per-service preset child modules (`ssh`, `mysql`, `https-443`, etc.)
  — the reference module itself retired that pattern in its v6 rewrite in
  favor of consumers declaring ports directly in the rules map; replicating
  ~60 thin wrapper modules would have added maintenance surface with no
  corresponding benefit.
- `vpc_associations`: an `aws_vpc_security_group_vpc_association` resource
  per entry, letting one security group's rules apply across additional
  VPCs beyond the one it was created in — instead of duplicating the same
  rule set per VPC. (Caught on a second pass against the reference
  module's full resource list after the initial scaffold missed it —
  the reference ships 5 root resources; the first pass here only
  implemented 4.)
- `examples/basic`: security group in a throwaway VPC, HTTPS inbound from
  anywhere, unrestricted outbound.
- `examples/complete`: demonstrates every rule-source type (CIDR, IPv6
  CIDR, `self = true`, `referenced_security_group_id`, `prefix_list_id`,
  single-port shorthand), `vpc_associations` against a secondary VPC, and
  custom `timeouts`. Uses this repo's own `vpc` module (relative path,
  same monorepo) rather than a bare inline VPC, so it also demonstrates
  real cross-module composition and inherits `vpc`'s secure-by-default
  posture instead of re-implementing a fraction of it inline.
- Terratest suite (`tests/terratest/security_group_test.go`) applying
  `examples/basic` and asserting against live AWS state; gated behind
  `AWS_TESTS_ENABLED` in CI per `docs/testing-strategy.md`.
