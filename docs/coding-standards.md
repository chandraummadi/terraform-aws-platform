# Coding Standards

This document is the **single source of truth** for conventions every module
in this repository must follow. It exists so that Sprint 2 (`vpc`) through
Sprint N are indistinguishable in style — a contributor who has read one
module's code should never be surprised by another's.

Before merging any module, verify it against this checklist. CI enforces the
automatable parts (fmt, lint, security scans); this document covers the
parts that require human judgment.

## 1. File Layout (mandatory, per module)

```
modules/<name>/
├── main.tf          # Resource definitions only
├── variables.tf      # All input variables, typed + described
├── outputs.tf        # All outputs, described
├── locals.tf          # Computed values, naming, tag merging
├── data.tf            # Data sources
├── versions.tf        # terraform{} + required_providers (NO provider block)
├── README.md           # terraform-docs generated + hand-written usage section
├── CHANGELOG.md         # Keep a Changelog format, one entry per release
├── examples/            # >= 1 runnable example (basic/), more for advanced features
└── tests/
    ├── terratest/        # Go tests
    └── fixtures/          # Supporting .tf fixtures used only by tests
```

Modules **do not** ship a `provider.tf` with a hardcoded provider block —
provider configuration is the caller's responsibility. This is what makes
modules composable across accounts/regions.

## 2. Naming Convention

Resource names follow: `<name_prefix>-<resource-type-suffix>`

```hcl
locals {
  name_prefix = var.name != "" ? var.name : "${var.project}-${var.environment}"
}

resource "aws_vpc" "this" {
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}
```

Rules:
- The primary resource in a module is always named `this` (e.g.
  `aws_vpc.this`, `aws_security_group.this`) — never a business-specific name.
  Collections use plural nouns keyed by `for_each` (e.g. `aws_subnet.private`).
- Never interpolate `var.environment` or `var.project` directly at 10
  different call sites — compute `local.name_prefix` once in `locals.tf`.
- All variables use `snake_case`. All module-local names use `this` or a
  short descriptive noun — never abbreviations that aren't industry-standard
  (`sg` and `vpc` are fine; `sgrp` is not).

## 3. Variable Conventions

- Every variable has `description` and `type`. No exceptions.
- Required variables have **no default**. Optional variables always have a
  sensible, secure-by-default value.
- Use `validation` blocks for anything with a constrained set of legal
  values (environment names, CIDR format, instance type family).
- Booleans are named as affirmative questions: `enable_nat_gateway`, not
  `disable_nat` or `no_nat`.
- Complex inputs use `object()` types with optional attributes
  (`optional(bool, false)`) rather than loosely-typed `any` or `map(any)`,
  so consumers get compile-time validation.

```hcl
variable "subnets" {
  description = "Map of subnet configurations keyed by logical name."
  type = map(object({
    cidr_block        = string
    availability_zone = string
    public            = optional(bool, false)
  }))
}
```

## 4. Tagging (DRY, applied identically everywhere)

Every module accepts `tags` (map(string), default `{}`) and merges it with
module-computed tags in `locals.tf`. Never scatter `merge()` calls with
inline tag literals across `main.tf`; centralize:

```hcl
# locals.tf
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "terraform-aws-platform/<module-name>"
  })
}
```

**Ownership (`Owner`, `CostCenter`, etc.) is deliberately NOT a dedicated
required variable.** It goes inside the caller-supplied `var.tags` map like
any other org-specific tag:

```hcl
module "vpc" {
  source = "..."
  name   = "payments-prod"
  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

This keeps the required-variable surface minimal per module (requirement:
"minimal required variables, optional advanced features") and avoids
every module needing its own opinion about what ownership metadata an org
tracks — some orgs use `Owner`, others `team`, others a cost-allocation
tag ID. `tags` is deliberately open-ended for that reason; do not add
`owner`, `cost_center`, or similar as a typed, required variable to any
module.

## 5. Security Defaults (non-negotiable)

- No ingress rule may default to `0.0.0.0/0` except where the resource's
  entire purpose requires public exposure (public ALB HTTP/HTTPS listener)
  — and even then it must be an explicit variable the caller can restrict.
- Storage resources (S3, EBS, RDS) default to encryption **on**, using a
  customer-managed KMS key when `var.kms_key_arn` is supplied, else the AWS
  managed key. Never default to unencrypted.
- IAM policies default to least-privilege scoped resources; `Resource = "*"`
  requires an inline comment justifying why (e.g. the action has no
  resource-level permissions support).
- No module hardcodes credentials, account IDs, or secrets. Account/region
  context always comes from data sources (`aws_caller_identity`,
  `aws_region`) or variables.
- Every module runs clean against `tflint`, `checkov`, and `tfsec` with zero
  high/critical findings before merge. Documented, justified exceptions go
  in a `.checkov.baseline` / inline `#checkov:skip=<CHECK_ID>: <reason>`.

## 6. Versioning Discipline

- Each module is tagged independently: `<module>/vX.Y.Z` (e.g. `vpc/v1.2.0`).
- `CHANGELOG.md` inside each module follows [Keep a Changelog](https://keepachangelog.com/).
- Breaking changes (removed variable, renamed output, changed default that
  alters existing infra behavior) require a **major** bump and a migration
  note in the CHANGELOG.

## 7. Documentation

- `README.md` is generated via `terraform-docs markdown table --output-file README.md --output-mode inject .`
  — the auto-generated block sits between `<!-- BEGIN_TF_DOCS -->` /
  `<!-- END_TF_DOCS -->` markers; hand-written usage/architecture notes go
  above and below those markers, never inside them (or the next
  `terraform-docs` run wipes them).
- Every module README includes: purpose, a minimal usage example, a link to
  `examples/`, and any Well-Architected notes specific to that module.

## 8. Testing

- Every module has a Terratest suite in `tests/terratest/` that:
  1. Applies the `examples/basic` configuration,
  2. Asserts on real AWS state via the AWS SDK (not just Terraform output),
  3. Destroys in a deferred cleanup, even on assertion failure.
- Tests must be runnable via `go test ./... -timeout 30m` and are wired
  into `.github/workflows/ci.yml`.

## 9. `count` vs `for_each`

Use `for_each` for anything keyed by a stable, named value (subnets, rules,
IAM policy attachments). Reserve `count` for simple homogeneous repetition
where index has no semantic meaning. This avoids the classic
"insert-in-the-middle reshuffles everything" `count` footgun.

## 10. Pull Request Definition of Done

A module PR is mergeable only when **all** of the following are true:

- [ ] `terraform fmt -recursive -check` passes
- [ ] `terraform validate` passes for the module and every example
- [ ] `tflint` clean
- [ ] `checkov` clean (or documented, justified skips)
- [ ] `tfsec` clean (or documented, justified skips)
- [ ] `terraform-docs` output committed and up to date
- [ ] Terratest suite passes in CI
- [ ] At least one example under `examples/` applies cleanly
- [ ] `CHANGELOG.md` updated
- [ ] Consistent with this document and with previously merged modules
