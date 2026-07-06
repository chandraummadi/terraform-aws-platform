# Testing Strategy

This platform has **no AWS account wired into CI**, by deliberate choice.
This document exists so that decision is explicit and doesn't get
"accidentally" reversed by a well-meaning PR that adds credentials to make
a red check go green.

## What runs in CI (no AWS account required)

| Check | Catches |
|---|---|
| `terraform fmt -check` | Formatting drift |
| `terraform validate` | Type errors, bad references, missing required arguments, invalid HCL |
| `tflint` | AWS-specific anti-patterns, deprecated syntax, naming convention violations |
| `checkov` / `tfsec` | Security misconfigurations (open ingress, missing encryption, over-broad IAM) |
| `terraform-docs` diff check | Stale README documentation |

These are **all static analysis** — none of them contact the AWS API, so
none of them need credentials. This is most of what actually catches bugs
before merge, and it's why `modules/<name>/examples/*` exist even without
apply-testing: a syntactically valid, lint-clean, security-scanned example
is still strong evidence the module is usable.

## What does NOT run in CI (needs a real AWS account)

- `terraform plan` — even planning requires live provider auth, because
  most modules read data sources (`aws_availability_zones`,
  `aws_caller_identity`, `aws_ami`, ...) that only resolve against a real
  account.
- Terratest (`tests/integration`, `tests/terratest` in each module) —
  applies real infrastructure, asserts against the live AWS SDK, then
  destroys it. This is the most valuable test category and the one every
  module's `tests/terratest/` directory should still be **written** for
  (per `docs/coding-standards.md` §8) — it's just not wired into this
  repo's CI, and is disabled by default via the `AWS_TESTS_ENABLED` repo
  variable in `.github/workflows/ci.yml`.

## How contributors validate a module before merging

1. All static checks above run in CI on every PR — the bar for CI is
   "green," not "everything possible."
2. Contributors with their own **personal or team sandbox AWS account**
   are expected to run `terraform plan`/`apply` against `examples/basic`
   and the module's Terratest suite locally before approving a module's
   first release (`v0.1.0`/`v1.0.0`) — this is called out explicitly in
   `docs/contributing.md`, "Code Review Expectations."
3. This keeps the bar for *contributing* to this repo low (no AWS account
   needed to open a PR, run linting, or review most changes) while keeping
   the bar for *shipping a first release* of a module honest (someone has
   actually applied it against real AWS at least once).

## If this repo later gets a shared CI AWS account

Should a dedicated CI/testing AWS account become available:

- Use **OIDC federation** (`aws-actions/configure-aws-credentials` with
  `role-to-assume`), never long-lived access keys as repo secrets.
- Scope the CI role's permissions tightly to what modules under test
  actually provision, and to a dedicated sandbox account — never a
  production or shared account.
- Flip `AWS_TESTS_ENABLED=true` as a repo/org variable; no workflow code
  changes needed, the gate already exists in `ci.yml`.
- Add a cleanup/cost-guard (e.g. a scheduled job that force-destroys
  anything left over from a failed test run) before enabling this broadly.

None of this is required to use this platform today — it's here so the
decision to skip it for now is a decision, not an oversight.
