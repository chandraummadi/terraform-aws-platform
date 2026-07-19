output "id" {
  description = "ID of the security group."
  value       = aws_security_group.this.id
}

output "arn" {
  description = "ARN of the security group."
  value       = aws_security_group.this.arn
}

output "name" {
  description = "Actual name of the security group (includes the random suffix when use_name_prefix = true)."
  value       = aws_security_group.this.name
}

output "vpc_id" {
  description = "ID of the VPC the security group belongs to."
  value       = aws_security_group.this.vpc_id
}

output "owner_id" {
  description = "AWS account ID that owns the security group."
  value       = aws_security_group.this.owner_id
}

output "ingress_rule_ids" {
  description = "Map of rule key (as declared in var.ingress_rules) => the created ingress rule's ID."
  value       = { for k, r in aws_vpc_security_group_ingress_rule.this : k => r.id }
}

output "egress_rule_ids" {
  description = "Map of rule key (as declared in var.egress_rules) => the created egress rule's ID."
  value       = { for k, r in aws_vpc_security_group_egress_rule.this : k => r.id }
}

output "vpc_association_ids" {
  description = "Map of association key (as declared in var.vpc_associations) => the vpc association resource's ID. Empty unless vpc_associations is set."
  value       = { for k, a in aws_vpc_security_group_vpc_association.this : k => a.id }
}
