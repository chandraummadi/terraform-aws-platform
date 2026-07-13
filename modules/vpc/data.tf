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
