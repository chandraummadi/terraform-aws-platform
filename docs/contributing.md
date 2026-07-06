# Contributing / Module Development Guidelines

Thank you for contributing. This document is the step-by-step guide for
adding a **new module** or modifying an existing one. Read
[`coding-standards.md`](coding-standards.md) first — this document is the
workflow; that one is the rulebook.

## Adding a New Module

1. **Open an issue first** using the "New Module Proposal" issue template.
   Describe the AWS service(s) covered, the minimal required variables, and
   which existing modules it composes with. This avoids duplicate or
   overlapping module proposals.
2. **Scaffold the directory** matching the mandatory layout in
   `coding-standards.md` §1:
   ```
   modules/<name>/{main,variables,outputs,locals,data,versions}.tf
   modules/<name>/{README.md,CHANGELOG.md}
   modules/<name>/examples/basic/
   modules/<name>/tests/terratest/
   ```
3. **Write variables and outputs first**, before resource bodies. This
   forces you to design the interface deliberately rather than exposing
   whatever fell out of the implementation.
4. **Implement `main.tf`**, following the security defaults in
   `coding-standards.md` §5 and the naming convention in §2.
5. **Write the `examples/basic` example** — this must be a complete,
   applyable root module (with its own `versions.tf` provider requirement)
   that exercises the new module with realistic-but-minimal inputs.
6. **Write the Terratest suite** in `tests/terratest/`, asserting against
   real AWS API state, not just `terraform output`.
7. **Run the local validation script** before opening a PR:
   ```bash
   ./scripts/validate.sh modules/<name>
   ```
8. **Generate docs**:
   ```bash
   terraform-docs markdown table --output-file README.md --output-mode inject modules/<name>
   ```
9. **Open the PR** against `main` using the PR template, and confirm every
   box in the Definition of Done checklist (`coding-standards.md` §10).

## Modifying an Existing Module

- Re-read that module's own `README.md` and `CHANGELOG.md` before changing
  anything — check whether your change is additive (minor/patch) or
  breaking (major) per `release-process.md`.
- Any change to a shared convention (naming, tagging, variable structure)
  must be applied consistently to *all* modules already merged, or
  explicitly called out as an intentional divergence with a reason in the
  PR description. Reviewers should block PRs that introduce silent
  inconsistency with prior modules.
- Update the module's `CHANGELOG.md` in the same PR — no batching changelog
  updates into a later "docs" PR.

## Local Development Setup

```bash
# Required tools
brew install terraform tflint terraform-docs
pip install checkov
brew install tfsec   # or: curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# Pre-commit hooks (formats, lints, docs on every commit)
pip install pre-commit
pre-commit install
```

## Code Review Expectations

- Reviewers check for **consistency with previously merged modules** as a
  first-class review criterion, not just correctness of the new module in
  isolation. If Sprint 2's `vpc` module used `enable_nat_gateway` as a
  variable name, Sprint 5's `ec2` module referencing NAT behavior must use
  the same term, not `nat_enabled` or `use_nat`.
- At least one reviewer must run the module's `examples/basic` against a
  real (sandbox) AWS account before approving a first release (`v0.1.0` /
  `v1.0.0`); subsequent patch/minor releases can rely on CI + Terratest.

## Reporting Issues

Use the "Bug Report" issue template for defects, "Feature Request" for new
variables/behavior on existing modules, and "New Module Proposal" for
entirely new modules. Include the module name and version in every issue
title, e.g. `[vpc/v1.2.0] secondary_cidr_blocks ignored when...`.
