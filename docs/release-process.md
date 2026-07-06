# Release Process

## Branching Strategy

- `main` — always releasable. Protected: requires passing CI + 1 approving review.
- `feature/<module>-<short-description>` — all work happens here, branched from `main`.
- `fix/<module>-<short-description>` — bug fixes, same rules as `feature/*`.
- No long-lived `develop` branch — trunk-based, short-lived branches only,
  merged via squash-merge to keep `main` history one-commit-per-change.

## Commit Convention

[Conventional Commits](https://www.conventionalcommits.org/), scoped to the
module touched, so changelogs and version bumps can (eventually) be
automated per module:

```
feat(vpc): add support for secondary CIDR blocks
fix(security-group): correct egress default for HTTPS-only rule set
docs(iam): clarify assume-role trust policy example
chore(ci): bump tflint action to v4
```

`feat` → minor bump for that module. `fix` → patch bump. `feat!` or a
`BREAKING CHANGE:` footer → major bump.

## Versioning Strategy (Semantic Versioning, per module)

Each module under `modules/<name>/` has its **own** version line, tagged as:

```
<module-name>/vMAJOR.MINOR.PATCH
```

Examples: `vpc/v1.0.0`, `vpc/v1.1.0`, `security-group/v1.0.0`.

- **MAJOR** — removed/renamed a required variable or output, changed a
  default in a way that alters existing infrastructure on `terraform apply`
  (e.g. flipping an encryption default would actually be a *fix*, not
  breaking, but renaming `subnet_ids` to `subnet_id_list` is breaking).
- **MINOR** — new optional variable, new resource behind a flag, new output.
  Fully backward compatible.
- **PATCH** — bug fix, doc fix, internal refactor with no interface change.

Root-level repository tags (`v1.0.0`, unscoped) are used only for
repository-wide milestones (e.g. "all Sprint 1–6 modules released") and are
not what consumers pin `source = "...?ref="` to.

## Release Steps (per module)

1. Merge module changes to `main` via PR (Definition of Done in
   `coding-standards.md` §10 must be satisfied).
2. Update `modules/<name>/CHANGELOG.md` with the new version section
   (Keep a Changelog format) as part of the same PR.
3. Once merged, tag: `git tag <module>/vX.Y.Z && git push origin <module>/vX.Y.Z`.
4. `.github/workflows/release.yml` triggers on the tag push, regenerates
   `terraform-docs` output as a final check, and creates a GitHub Release
   with the CHANGELOG section as release notes.
5. Consumers bump their `?ref=` pin on their own schedule — nothing is
   force-pushed or auto-upgraded.

## Deprecation Policy

- A module (or a variable within it) being deprecated gets a `DEPRECATED:`
  prefix in its `description`, remains functional for at least one MAJOR
  version cycle, and is documented in the CHANGELOG under a `Deprecated`
  heading before removal.

## Optional: Registry Mirror Distribution

Independently of the git-ref release above, a module can *additionally* be
published to the Terraform Registry (public or private/Terraform Cloud) as
a standalone `terraform-aws-<name>` repo. This is opt-in per module via
`.registry-modules.yml` and is handled entirely by the
`mirror-to-registry-repo` job in `release.yml` — it runs after the normal
GitHub Release step and requires no change to the module's own code, tags,
or CHANGELOG. See `docs/architecture.md`, "Distribution Model", for why
this is opt-in rather than the default: the public registry's one-repo-per-
module requirement is incompatible with keeping this platform as a single
monorepo, so registry distribution is treated as a secondary, generated
channel rather than restructuring the whole repo around it.

## Pre-1.0 Modules

Any module still under `v0.x.y` is explicitly unstable — breaking changes
are allowed on MINOR bumps, per SemVer's own pre-1.0 carve-out. A module
graduates to `v1.0.0` once it has: a Terratest suite, a Checkov/tfsec clean
scan, and has been consumed by at least one `examples/` composition
successfully.
