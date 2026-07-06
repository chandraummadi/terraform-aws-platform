## Description

<!-- What does this PR do? -->

## Module(s) affected

<!-- e.g. modules/vpc — one PR per module is strongly preferred -->

## Type of change

- [ ] New module
- [ ] Feature (backward compatible)
- [ ] Fix (backward compatible)
- [ ] Breaking change (requires a MAJOR version bump — see docs/release-process.md)
- [ ] Docs / CI / tooling only

## Definition of Done (docs/coding-standards.md §10)

- [ ] `terraform fmt -recursive -check` passes
- [ ] `terraform validate` passes for the module and every example
- [ ] TFLint clean
- [ ] Checkov clean (or documented, justified inline skips — no blanket CI skips)
- [ ] tfsec clean (or documented, justified inline skips)
- [ ] `terraform-docs` output committed and current
- [ ] Terratest suite passes
- [ ] At least one example under `examples/` applies cleanly
- [ ] `modules/<name>/CHANGELOG.md` updated with this version's entry
- [ ] Consistent with `docs/coding-standards.md` and with previously merged modules (naming, tagging, variable style)

## Notes for reviewers

<!-- Anything a reviewer should specifically check, e.g. "first release of this module, please terraform apply examples/basic against a sandbox account before approving" -->
