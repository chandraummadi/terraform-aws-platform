output "security_group_id" {
  value = module.security_group.id
}

output "ingress_rule_ids" {
  value = module.security_group.ingress_rule_ids
}

output "egress_rule_ids" {
  value = module.security_group.egress_rule_ids
}

output "vpc_association_ids" {
  value = module.security_group.vpc_association_ids
}
