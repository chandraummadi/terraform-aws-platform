## ---------------------------------------------------------------------------
## Security Group
## ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  #checkov:skip=CKV2_AWS_5: This module's entire purpose is to produce a standalone, reusable security group (per this repo's "composable, not monolithic" design principle) — attachment to an EC2 instance, ENI, ALB, or Lambda happens in a CONSUMING module (ec2/alb/lambda, later sprints), never here. Any call site that only invokes this module in isolation (as examples/basic does, deliberately, to demonstrate this module alone) will always show as "unattached" to a same-module static scan, without that being a real security gap.
  region = var.region

  name                   = var.use_name_prefix ? null : var.name
  name_prefix            = var.use_name_prefix ? "${var.name}-" : null
  description            = coalesce(var.description, "Managed by Terraform (terraform-aws-platform/security-group: ${var.name})")
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = var.revoke_rules_on_delete

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
    }
  }

  tags = merge(local.common_tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

## ---------------------------------------------------------------------------
## Ingress rules — standalone resources, not inline blocks (see variables.tf
## comment): adding/removing one rule never forces replacement of the
## security group or any other rule.
## ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  region = var.region

  security_group_id = aws_security_group.this.id

  description                  = each.value.description
  from_port                    = try(coalesce(each.value.from_port, each.value.to_port), null)
  to_port                      = try(coalesce(each.value.to_port, each.value.from_port), null)
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = merge(local.common_tags, each.value.tags, {
    Name = each.key
  })
}

## ---------------------------------------------------------------------------
## Egress rules
## ---------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  region = var.region

  security_group_id = aws_security_group.this.id

  description                  = each.value.description
  from_port                    = try(coalesce(each.value.from_port, each.value.to_port), null)
  to_port                      = try(coalesce(each.value.to_port, each.value.from_port), null)
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = merge(local.common_tags, each.value.tags, {
    Name = each.key
  })
}

## ---------------------------------------------------------------------------
## Exclusive rule enforcement (secure-by-default: on unless explicitly
## disabled — see variables.tf for the tradeoff this represents)
## ---------------------------------------------------------------------------

resource "aws_vpc_security_group_rules_exclusive" "this" {
  count = var.enable_exclusive_rules ? 1 : 0

  region = var.region

  security_group_id = aws_security_group.this.id
  ingress_rule_ids  = [for rule in aws_vpc_security_group_ingress_rule.this : rule.id]
  egress_rule_ids   = [for rule in aws_vpc_security_group_egress_rule.this : rule.id]
}

## ---------------------------------------------------------------------------
## VPC Associations — share this security group with additional VPCs beyond
## var.vpc_id (opt-in, empty by default)
## ---------------------------------------------------------------------------

resource "aws_vpc_security_group_vpc_association" "this" {
  for_each = var.vpc_associations

  region = var.region

  security_group_id = aws_security_group.this.id
  vpc_id            = each.value.vpc_id
}
