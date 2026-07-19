locals {
  name_prefix = var.name

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "terraform-aws-platform/security-group"
  })
}
