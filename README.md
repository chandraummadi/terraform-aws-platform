# terraform-aws-platform

Production-grade, reusable Terraform module library for AWS, built to HashiCorp
best practices and the AWS Well-Architected Framework. Designed for enterprise
consumption: every module is independently versioned, tested, documented, and
scanned for security and cost issues before it ships.

## Status

| Sprint | Deliverable            | Status      |
|--------|-------------------------|-------------|
| 1      | Repository skeleton     | ✅ Complete |
| 2      | `modules/vpc`            | 🔜 Next     |
| 3      | `modules/security-group` | ⏳ Planned  |
| 4      | `modules/iam`            | ⏳ Planned  |
| 5      | `modules/ec2`            | ⏳ Planned  |
| 6      | `modules/alb`            | ⏳ Planned  |

Each sprint ships a module that is fully consistent with the ones before it —
same file layout, same variable-naming conventions, same tagging strategy,
same test harness — so consumers can compose them without surprises.

## Design Principles

1. **Secure by default.** No module ships with permissive defaults
   (`0.0.0.0/0` ingress, unencrypted storage, wildcard IAM). Insecure
   behavior must be an explicit opt-in via a variable, never the default.
2. **Minimal required inputs, rich optional inputs.** A consumer should be
   able to call a module with 2–4 variables for the common case, while
   still being able to reach every AWS feature through optional variables.
3. **Composable, not monolithic.** Modules expose IDs/ARNs/names as outputs
   so they can be wired together (e.g. `security-group` output feeding
   `ec2`), rather than each module trying to own the whole stack.
4. **DRY.** Shared logic (naming, tagging, validation patterns) is
   documented once in [`docs/coding-standards.md`](docs/coding-standards.md)
   and applied identically across modules — never copy-pasted and drifted.
5. **Verifiable.** Every module ships `terraform-docs`-generated
   documentation, a Terratest suite, TFLint/Checkov/tfsec clean scans, and
   at least one runnable example.

## Repository Layout

```
terraform-aws-platform/
├── .github/              # CI/CD workflows, issue & PR templates
├── docs/                 # Architecture, standards, contributing, release process
├── examples/             # Root-level composed examples (multiple modules together)
├── scripts/              # Local dev helper scripts (fmt, validate, release)
├── tests/integration/    # Cross-module integration tests
└── modules/              # One directory per module (the actual product)
    ├── vpc/
    ├── security-group/
    ├── iam/
    ├── ec2/
    ├── alb/
    └── ... (see table below)
```

## Module Catalogue

| Module              | Purpose                                   | Sprint |
|---------------------|--------------------------------------------|--------|
| `vpc`               | VPC, subnets, route tables, NAT/IGW        | 2      |
| `security-group`    | Security groups + rule sets                | 3      |
| `iam`               | IAM roles, policies, instance profiles     | 4      |
| `ec2`                | EC2 instances / launch templates / ASG    | 5      |
| `alb`                | Application Load Balancer                 | 6      |
| `nlb`                | Network Load Balancer                     | later  |
| `route53`            | DNS zones and records                     | later  |
| `lambda`             | Lambda functions                          | later  |
| `eks`                | EKS clusters and node groups               | later  |
| `rds`                | Managed relational databases               | later  |
| `kms`                | Customer-managed KMS keys                  | later  |
| `ebs`                | EBS volumes                                | later  |
| `s3`                 | S3 buckets with secure defaults            | later  |
| `ecr`                | Container registries                       | later  |
| `cloudwatch`         | Alarms, dashboards, log groups             | later  |
| `backup`             | AWS Backup plans/vaults                    | later  |
| `secrets-manager`    | Secrets Manager secrets                    | later  |

## Requirements

- Terraform `>= 1.6`
- AWS Provider `~> 6.0`
- [tflint](https://github.com/terraform-linters/tflint), [checkov](https://www.checkov.io/), [tfsec](https://aquasecurity.github.io/tfsec/), [terraform-docs](https://terraform-docs.io/) installed locally for pre-commit checks (also run in CI)

## Using a Module

Every module is consumable directly from this repo, pinned to a tag:

```hcl
module "vpc" {
  source  = "git::https://github.com/<org>/terraform-aws-platform.git//modules/vpc?ref=vpc/v1.0.0"

  name        = "payments-prod"
  environment = "prod"
  cidr_block  = "10.20.0.0/16"

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

Per-module tags (`vpc/v1.0.0`, `security-group/v1.2.1`, ...) let each module
follow **independent Semantic Versioning** — a breaking change in `ec2`
should never force a version bump in `vpc`. See
[`docs/release-process.md`](docs/release-process.md).

Modules listed in [`.registry-modules.yml`](.registry-modules.yml) are
*also* mirrored to a standalone repo on release, so they can alternatively
be consumed via the Terraform Registry:

```hcl
module "vpc" {
  source  = "app.terraform.io/<org>/vpc/aws"
  version = "1.0.0"
}
```

Both point at identical, reviewed code — pick whichever fits your tooling.
See [`docs/architecture.md`](docs/architecture.md) ("Distribution Model")
for why the git-ref path is the default and the registry path is opt-in.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — Well-Architected mapping, design decisions
- [`docs/coding-standards.md`](docs/coding-standards.md) — naming, tagging, variable conventions
- [`docs/contributing.md`](docs/contributing.md) — how to add/modify a module
- [`docs/release-process.md`](docs/release-process.md) — branching, versioning, release strategy

## License

[Apache License 2.0](LICENSE)
=======
