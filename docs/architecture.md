# Architecture

## Purpose

`terraform-aws-platform` is a library, not an application deployment. It
produces versioned, composable Terraform modules that other repositories
(landing zones, application infra repos) consume. This document explains the
architectural decisions and how each maps to the AWS Well-Architected
Framework.

## Well-Architected Mapping

| Pillar                  | How this library addresses it |
|--------------------------|--------------------------------|
| **Operational Excellence** | terraform-docs auto-generated docs, CHANGELOG per module, CI enforces fmt/validate/lint before merge, Terratest gives fast feedback on regressions. |
| **Security**              | Secure-by-default variables (no open ingress, encryption on by default), Checkov + tfsec gates in CI, least-privilege IAM patterns in `docs/coding-standards.md`, no hardcoded secrets. |
| **Reliability**           | Modules expose Multi-AZ options as first-class variables (not afterthoughts), outputs designed for cross-module composition so failure domains stay isolated per module. |
| **Performance Efficiency** | Modules avoid hardcoding instance families/sizes; sizing is always a variable with a documented rationale for the default. |
| **Cost Optimization**     | No module defaults to always-on expensive resources (e.g. NAT Gateway count defaults to 1 per AZ only if `enable_high_availability = true`, otherwise a single shared NAT); tagging strategy supports cost allocation. |
| **Sustainability**        | Defaults favor right-sized resources over oversized ones; modules make it easy to scale down non-prod environments (e.g. `environment != "prod"` can disable HA add-ons). |

## Composition Model

Modules are deliberately narrow — one module, one AWS concern — so that
composition happens at the caller level:

```
                 ┌───────────────┐
                 │   modules/vpc  │
                 └───────┬───────┘
                          │ vpc_id, subnet_ids
                          ▼
                 ┌────────────────────────┐
                 │ modules/security-group  │
                 └───────┬─────────────────┘
                          │ security_group_id
                          ▼
        ┌─────────────────┴──────────────────┐
        ▼                                    ▼
┌───────────────┐                   ┌────────────────┐
│  modules/ec2   │                   │  modules/alb    │
└───────────────┘                   └────────────────┘
        ▲                                    │
        └──────────── target group ──────────┘
```

This mirrors how `examples/production` composes modules together, and is
the pattern Sprint 5 (EC2) and Sprint 6 (ALB) will demonstrate concretely.

## State & Environment Separation (guidance for consumers)

This repo does not itself manage remote state — it produces modules. When
consumed, callers are expected to:

- Use one remote state backend (S3 + DynamoDB lock table, or Terraform
  Cloud) per environment, never share state across `dev`/`staging`/`prod`.
- Use Terragrunt (or plain root modules per environment) to keep
  environment-specific `.tfvars` separate from module source, so a module
  version bump can be rolled out to `dev` before `prod`.
- Pin module `source` refs to a tag (`?ref=vpc/v1.2.0`), never to `main`, in
  any environment beyond a local sandbox.

## Multi-Account Guidance

The `examples/multi-account` example (populated in a later sprint once
`iam` and `vpc` exist) demonstrates cross-account VPC peering /
Transit Gateway attachment plus cross-account IAM assume-role patterns,
using the `docs/coding-standards.md` §5 "Side effects must be obvious" rule
for anything that touches another account's resources.

## Distribution Model

This platform supports **two** distribution channels, deliberately kept
asymmetric so the default path stays simple:

1. **Monorepo + git-ref (default, zero extra steps).** Every module is
   consumed straight from this repo, pinned to its own tag:
   ```hcl
   module "vpc" {
     source = "git::https://github.com/<org>/terraform-aws-platform.git//modules/vpc?ref=vpc/v1.0.0"
   }
   ```
   This is what every module gets automatically the moment it's tagged
   (`.github/workflows/release.yml`, `release` job). No opt-in required.

2. **Public/private Terraform Registry mirror (opt-in, per module).** The
   Terraform Registry's `source`/`version` syntax —
   ```hcl
   module "vpc" {
     source  = "app.terraform.io/<org>/vpc/aws"
     version = "1.0.0"
   }
   ```
   — requires **one repo per module** (named `terraform-aws-<name>`); it
   cannot serve a `modules/vpc` subdirectory out of a monorepo. Rather than
   restructure the whole platform around that constraint, a module that
   specifically wants registry distribution is listed in
   `.registry-modules.yml`; on release, CI subtree-splits `modules/<name>`
   into a dedicated mirror repo and tags it there (`release.yml`,
   `mirror-to-registry-repo` job). The monorepo stays the source of truth;
   the mirror is a generated artifact, never edited directly.

Consumers choose whichever channel fits their tooling — both point at
identical, review-gated code, just packaged differently.

## Why Independent Module Versioning

A single repo-wide version (`v3.4.0` for everything) would force consumers
to accept unrelated changes (e.g. an `rds` bugfix) just to get an `ec2`
feature. Instead each module directory is tagged independently
(`ec2/v2.1.0`, `rds/v1.0.3`), following semver strictly within that module's
own history. See `docs/release-process.md` for the exact tagging and
release mechanics.
