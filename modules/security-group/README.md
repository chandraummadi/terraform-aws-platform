# security-group

Creates a single AWS security group with ingress/egress rules declared as
typed, named rule maps. Rules are implemented as standalone
`aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule`
resources rather than inline blocks — see "Design note" below.

## Design note: standalone rule resources, no per-service presets

**Standalone rule resources.** Historically, security group modules (and
the `aws_security_group` resource itself) declared rules as inline
`ingress {}` / `egress {}` blocks. That pattern has a real operational cost:
Terraform treats the entire set of inline blocks as one attribute, so
adding or removing a single rule forces a diff — and in some provider
versions, replacement — touching every other rule at the same time. This
module uses the standalone `aws_vpc_security_group_ingress_rule` /
`_egress_rule` resources instead, so each rule is tracked and
changed independently. This matches the direction
`terraform-aws-modules/terraform-aws-security-group` took in its v6.0.0
rewrite (June 2026).

**No per-service preset child modules.** Older security-group module
designs (including earlier versions of the reference above) shipped dozens
of child modules — one each for `ssh`, `mysql`, `https-443`, `redis`, and
so on — as thin wrappers presetting well-known ports. The reference
module's own v6 rewrite retired that pattern in favor of consumers
declaring `from_port`/`to_port`/`ip_protocol` directly in the rules map.
This module follows that same conclusion: a preset-module catalog is
maintenance surface (every AWS service, every port convention, forever)
with no capability a two-line rule object doesn't already provide.

## Well-Architected notes

- **Security pillar**: `ingress_rules` and `egress_rules` both default to
  `{}` — this module opens zero ports on its own. Every rule requires
  exactly one explicit traffic source (`cidr_ipv4`, `cidr_ipv6`,
  `prefix_list_id`, `referenced_security_group_id`, or `self = true`); a
  rule that supplies none or several of these fails validation before
  `apply`.
- **Security pillar / drift control**: `enable_exclusive_rules` defaults to
  `true`. Terraform actively reverts any rule added to this security group
  outside this module's config (AWS console, CLI, another Terraform run)
  on the next apply. This is deliberately strict — if a team relies on
  manually hotfixing security group rules during an incident, that rule
  disappears on the next `apply` unless it's added to `ingress_rules` /
  `egress_rules` here. Set `enable_exclusive_rules = false` if you have a
  documented reason to allow that coexistence.
- **Operational excellence pillar**: `use_name_prefix` defaults to `true`
  and the security group has `create_before_destroy = true`, so replacing
  this security group (e.g. changing `description`, which forces
  replacement) never collides with the old one still being deleted.

## Usage

Minimal (common case — 3 required variables):

```hcl
module "app_sg" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/security-group?ref=security-group/v1.0.0"

  name        = "payments-app"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

That alone creates a security group with **zero rules** (secure by
default) — add rules explicitly:

```hcl
module "app_sg" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/security-group?ref=security-group/v1.0.0"

  name        = "payments-app"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    https_from_alb = {
      description                  = "HTTPS from the ALB security group"
      from_port                    = 443
      to_port                      = 443
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
    }
    self_cluster_traffic = {
      description = "Allow members of this SG to reach each other"
      from_port   = 0
      to_port     = 65535
      ip_protocol = "tcp"
      self        = true
    }
  }

  egress_rules = {
    all_outbound_ipv4 = {
      description = "Allow all outbound IPv4"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

See [`examples/basic`](examples/basic) for a minimal, self-contained
configuration, or [`examples/complete`](examples/complete) for every
rule-source type plus `vpc_associations` composed with this repo's own
`vpc` module.

### Sharing one security group across multiple VPCs

```hcl
module "shared_sg" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/security-group?ref=security-group/v1.0.0"

  name        = "shared-egress-baseline"
  environment = "prod"
  vpc_id      = module.vpc_a.vpc_id

  vpc_associations = {
    vpc_b = { vpc_id = module.vpc_b.vpc_id }
    vpc_c = { vpc_id = module.vpc_c.vpc_id }
  }

  egress_rules = {
    all_outbound = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.50 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.55.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_rules_exclusive.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_rules_exclusive) | resource |
| [aws_vpc_security_group_vpc_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_vpc_association) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | Description of the security group. AWS defaults this to "Managed by Terraform" if left null — set something meaningful, since this field can't be changed without replacing the security group. | `string` | `null` | no |
| <a name="input_egress_rules"></a> [egress\_rules](#input\_egress\_rules) | Map (keyed by a logical name you choose, becomes each rule's Name tag) of egress rules to add to the security group. Empty by default — set at least one rule (commonly full outbound to 0.0.0.0/0 and/or ::/0) or the security group permits no outbound traffic at all, which is secure but easy to forget and debug. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>    tags                         = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_exclusive_rules"></a> [enable\_exclusive\_rules](#input\_enable\_exclusive\_rules) | Whether Terraform enforces that ONLY the rules declared in ingress\_rules/egress\_rules exist on this security group. When true (the default), any rule added out-of-band — via the AWS console, CLI, or another Terraform configuration — is deleted on the next apply. This is a deliberate secure-by-default / drift-correcting choice: set false only if you have a documented reason to let this security group coexist with rules managed outside this module call. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Used in local.common\_tags. | `string` | n/a | yes |
| <a name="input_ingress_rules"></a> [ingress\_rules](#input\_ingress\_rules) | Map (keyed by a logical name you choose, becomes each rule's Name tag) of ingress rules to add to the security group. Empty by default — this module never opens any port on its own. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>    tags                         = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the security group. Used as the resource Name (or name\_prefix, per use\_name\_prefix) and as the tag prefix for every rule this module creates. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region override applied to every resource in this module via the provider's per-resource `region` argument. Leave null to use the provider's configured region. | `string` | `null` | no |
| <a name="input_revoke_rules_on_delete"></a> [revoke\_rules\_on\_delete](#input\_revoke\_rules\_on\_delete) | Whether Terraform revokes all of this security group's rules before deleting the group itself. Mainly relevant for security groups AWS won't let you delete while rules still reference them from elsewhere; leave false unless you've hit that specific problem. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the security group and every rule this module creates, merged with module-computed tags (Environment, ManagedBy, Module). Ownership metadata (Owner, CostCenter, etc.) belongs here — see docs/coding-standards.md §4 — this module deliberately has no dedicated owner variable. | `map(string)` | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Create/delete timeout overrides for the security group resource. | <pre>object({<br/>    create = optional(string)<br/>    delete = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_use_name_prefix"></a> [use\_name\_prefix](#input\_use\_name\_prefix) | Whether name is used as a name\_prefix (AWS appends a random suffix) instead of an exact name. Defaults to true so re-creating this security group (e.g. via create\_before\_destroy) never collides with the old one still being deleted. | `bool` | `true` | no |
| <a name="input_vpc_associations"></a> [vpc\_associations](#input\_vpc\_associations) | Map (keyed by a logical name you choose) of additional VPC IDs to associate this security group with, beyond the VPC it was created in (var.vpc\_id). Lets one security group's rules apply across multiple VPCs instead of duplicating the same rule set per VPC. | <pre>map(object({<br/>    vpc_id = string<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the security group belongs to (e.g. module.vpc.vpc\_id). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the security group. |
| <a name="output_egress_rule_ids"></a> [egress\_rule\_ids](#output\_egress\_rule\_ids) | Map of rule key (as declared in var.egress\_rules) => the created egress rule's ID. |
| <a name="output_id"></a> [id](#output\_id) | ID of the security group. |
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | Map of rule key (as declared in var.ingress\_rules) => the created ingress rule's ID. |
| <a name="output_name"></a> [name](#output\_name) | Actual name of the security group (includes the random suffix when use\_name\_prefix = true). |
| <a name="output_owner_id"></a> [owner\_id](#output\_owner\_id) | AWS account ID that owns the security group. |
| <a name="output_vpc_association_ids"></a> [vpc\_association\_ids](#output\_vpc\_association\_ids) | Map of association key (as declared in var.vpc\_associations) => the vpc association resource's ID. Empty unless vpc\_associations is set. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the security group belongs to. |
<!-- END_TF_DOCS -->
