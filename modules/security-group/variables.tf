## ---------------------------------------------------------------------------
## Required (minimal surface for the common case)
## ---------------------------------------------------------------------------

variable "name" {
  description = "Name of the security group. Used as the resource Name (or name_prefix, per use_name_prefix) and as the tag prefix for every rule this module creates."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 40
    error_message = "name must be between 1 and 40 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Used in local.common_tags."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "shared"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, shared."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the security group belongs to (e.g. module.vpc.vpc_id)."
  type        = string
}

variable "region" {
  description = "AWS region override applied to every resource in this module via the provider's per-resource `region` argument. Leave null to use the provider's configured region."
  type        = string
  default     = null
}

## ---------------------------------------------------------------------------
## Optional — security group core
## ---------------------------------------------------------------------------

variable "description" {
  description = "Description of the security group. AWS defaults this to \"Managed by Terraform\" if left null — set something meaningful, since this field can't be changed without replacing the security group."
  type        = string
  default     = null
}

variable "use_name_prefix" {
  description = "Whether name is used as a name_prefix (AWS appends a random suffix) instead of an exact name. Defaults to true so re-creating this security group (e.g. via create_before_destroy) never collides with the old one still being deleted."
  type        = bool
  default     = true
}

variable "revoke_rules_on_delete" {
  description = "Whether Terraform revokes all of this security group's rules before deleting the group itself. Mainly relevant for security groups AWS won't let you delete while rules still reference them from elsewhere; leave false unless you've hit that specific problem."
  type        = bool
  default     = false
}

variable "timeouts" {
  description = "Create/delete timeout overrides for the security group resource."
  type = object({
    create = optional(string)
    delete = optional(string)
  })
  default = null
}

## ---------------------------------------------------------------------------
## Optional — Ingress / Egress rules
## ---------------------------------------------------------------------------
## Rules use standalone aws_vpc_security_group_ingress_rule /
## aws_vpc_security_group_egress_rule resources (not inline ingress {} /
## egress {} blocks on aws_security_group) so adding or removing one rule
## never forces replacement of the security group or any other rule —
## matches the current terraform-aws-modules/terraform-aws-security-group
## v6 design, which moved off inline blocks for the same reason.
##
## Each rule must set EXACTLY ONE traffic source: cidr_ipv4, cidr_ipv6,
## prefix_list_id, referenced_security_group_id, or self = true (self is a
## distinct typed field here, not a magic "self" string sentinel, per
## docs/coding-standards.md §3's preference for typed object() over
## stringly-typed values).
##
## Secure by default: both maps default to {} — this module creates a
## security group with ZERO rules unless you declare them. There is no
## synthesized "allow common ports" fallback.

variable "ingress_rules" {
  description = "Map (keyed by a logical name you choose, becomes each rule's Name tag) of ingress rules to add to the security group. Empty by default — this module never opens any port on its own."
  type = map(object({
    description                  = optional(string)
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
    tags                         = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.ingress_rules :
      length(compact([v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id])) + (v.self ? 1 : 0) == 1
    ])
    error_message = "Each ingress_rules entry must set exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self = true."
  }
}

variable "egress_rules" {
  description = "Map (keyed by a logical name you choose, becomes each rule's Name tag) of egress rules to add to the security group. Empty by default — set at least one rule (commonly full outbound to 0.0.0.0/0 and/or ::/0) or the security group permits no outbound traffic at all, which is secure but easy to forget and debug."
  type = map(object({
    description                  = optional(string)
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
    tags                         = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.egress_rules :
      length(compact([v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id])) + (v.self ? 1 : 0) == 1
    ])
    error_message = "Each egress_rules entry must set exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self = true."
  }
}

variable "enable_exclusive_rules" {
  description = "Whether Terraform enforces that ONLY the rules declared in ingress_rules/egress_rules exist on this security group. When true (the default), any rule added out-of-band — via the AWS console, CLI, or another Terraform configuration — is deleted on the next apply. This is a deliberate secure-by-default / drift-correcting choice: set false only if you have a documented reason to let this security group coexist with rules managed outside this module call."
  type        = bool
  default     = true
}

## ---------------------------------------------------------------------------
## Optional — VPC Associations (share this SG with additional VPCs)
## ---------------------------------------------------------------------------
## AWS lets a security group created in one VPC additionally apply to other
## VPCs (e.g. peered or Resource Access Manager-shared VPCs), instead of
## every VPC needing its own copy of the same rules. Empty by default — the
## security group only applies to var.vpc_id unless you opt in here.

variable "vpc_associations" {
  description = "Map (keyed by a logical name you choose) of additional VPC IDs to associate this security group with, beyond the VPC it was created in (var.vpc_id). Lets one security group's rules apply across multiple VPCs instead of duplicating the same rule set per VPC."
  type = map(object({
    vpc_id = string
  }))
  default = {}
}

## ---------------------------------------------------------------------------
## Tags
## ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to the security group and every rule this module creates, merged with module-computed tags (Environment, ManagedBy, Module). Ownership metadata (Owner, CostCenter, etc.) belongs here — see docs/coding-standards.md §4 — this module deliberately has no dedicated owner variable."
  type        = map(string)
  default     = {}
}
