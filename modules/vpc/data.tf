data "aws_availability_zones" "available" {
  state = "available"

  # Exclude AZs that can't host every resource type (e.g. some Local Zones
  # opted in at the account level) so auto-selection never picks an AZ that
  # would fail on subnet/NAT Gateway creation.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Only needed to build a real (non-wildcard) Resource ARN for the
# self-contained flow-log IAM policy — see local.create_flow_log_cloudwatch_iam_role.
data "aws_region" "current" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  region = var.region
}

data "aws_caller_identity" "current" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0
}

data "aws_partition" "current" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0
}
