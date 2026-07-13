# vpc

Creates a VPC with public/private subnets across one or more availability
zones, Internet Gateway + public routing, optional NAT Gateway egress for
private subnets (single, one-per-AZ, or none), optional custom Network
ACLs, and optional VPC Flow Logs to a caller-supplied destination.

## Design note: why NAT Gateway and NACLs are inline, not child modules

Neither is independently versioned or ever called directly by a consumer —
only this top-level module gets a semver tag (`vpc/vX.Y.Z`, per
`docs/coding-standards.md` §6). A submodule boundary here would add a second
place to read when tracing NAT/route logic and a second terraform-docs
table to keep in sync, with no consumer-facing benefit in return. This
mirrors `terraform-aws-modules/terraform-aws-vpc` (the de facto community
standard for this exact module), which keeps NAT/NACL logic inline and only
breaks out genuinely optional bolt-ons (`flow-log`, `vpc-endpoints`) as
child modules.

## Well-Architected notes

- **Security pillar**: no ingress rule ever defaults to `0.0.0.0/0` here —
  this module creates no security groups and, by default, no custom Network
  ACLs (subnets keep the VPC's default allow-all NACL, matching AWS's own
  default). If you opt into `manage_public_network_acl` /
  `manage_private_network_acl`, the resulting NACL is deny-all until you
  supply explicit rules — there's no synthesized fallback.
- **Reliability pillar**: `nat_gateway_strategy = "one_per_az"` gives each
  AZ its own NAT Gateway so an AZ-level NAT outage doesn't take down every
  private subnet's egress; `"single"` trades that isolation for lower cost.
- **Cost optimization pillar**: `nat_gateway_strategy` defaults to `"single"`
  (one NAT Gateway + one EIP total) rather than one-per-AZ, since most
  non-production and many production workloads don't need per-AZ NAT
  redundancy to justify the ~3x cost.
- **Operational excellence pillar**: this module never creates the flow
  log's CloudWatch Log Group, S3 bucket, or IAM role — pass in an existing
  `flow_log_destination_arn` from the `cloudwatch`/`s3`/`iam` modules. Keeps
  this module composable rather than trying to own the whole observability
  stack.

## NAT Gateway scenarios

`nat_gateway_strategy` controls how private subnets reach the internet:

- **`single`** (default) — one NAT Gateway + one EIP total, placed in the
  first AZ. Lowest cost; that AZ becoming unavailable takes down egress for
  every private subnet until it recovers.
- **`one_per_az`** — one NAT Gateway + EIP per AZ. Full AZ isolation: a NAT
  outage in one AZ doesn't affect the others. Costs roughly N× the single
  strategy for N AZs.
- **`none`** — no NAT Gateway created at all. Use this when private subnets
  either don't need outbound internet (VPC endpoints only) or reach it some
  other way (Transit Gateway, NAT instance you manage yourself, etc.).

## Usage

Minimal (common case — 3 required variables):

```hcl
module "vpc" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/vpc?ref=vpc/v1.0.0"

  name        = "payments-prod"
  environment = "prod"
  cidr_block  = "10.20.0.0/16"

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

Full-HA example, explicit AZs/CIDRs, custom private NACL, flow logs to an
existing CloudWatch Log Group:

```hcl
module "vpc" {
  source = "git::https://github.com/chandraummadi/terraform-aws-platform.git//modules/vpc?ref=vpc/v1.0.0"

  name        = "payments-prod"
  environment = "prod"
  cidr_block  = "10.20.0.0/16"

  availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs   = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs  = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  nat_gateway_strategy  = "one_per_az"

  enable_flow_logs         = true
  flow_log_destination_arn = module.cloudwatch.log_group_arn
  flow_log_iam_role_arn    = module.iam.flow_log_role_arn

  manage_private_network_acl = true
  private_network_acl_ingress_rules = [
    { rule_number = 100, protocol = "-1", rule_action = "allow", cidr_block = "10.20.0.0/16", from_port = 0, to_port = 0 },
  ]
  private_network_acl_egress_rules = [
    { rule_number = 100, protocol = "-1", rule_action = "allow", cidr_block = "0.0.0.0/0", from_port = 0, to_port = 0 },
  ]

  tags = {
    Owner      = "platform-team"
    CostCenter = "eng-infra"
  }
}
```

See [`examples/basic`](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!--
  Generated via:
    terraform-docs markdown table --output-file README.md --output-mode inject .
  Run this for real once `terraform-docs` is available in the environment
  used to author this module — the table below is hand-authored to match
  main.tf/variables.tf/outputs.tf exactly, but treat this marker block as
  the source of truth going forward and let the tool regenerate it on every
  change so it can't drift.
-->

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.15.5 |
| aws | >= 6.50 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 6.50 |

## Resources

| Name | Type |
|------|------|
| aws_vpc.this | resource |
| aws_internet_gateway.this | resource |
| aws_subnet.public | resource |
| aws_subnet.private | resource |
| aws_route_table.public | resource |
| aws_route.public_internet_gateway | resource |
| aws_route_table_association.public | resource |
| aws_eip.nat | resource |
| aws_nat_gateway.this | resource |
| aws_route_table.private | resource |
| aws_route.private_nat_gateway | resource |
| aws_route_table_association.private | resource |
| aws_network_acl.public | resource |
| aws_network_acl.private | resource |
| aws_flow_log.this | resource |
| aws_availability_zones.available | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name identifier for this VPC, used as the resource name prefix. | `string` | n/a | yes |
| environment | Deployment environment: dev, staging, prod, or shared. | `string` | n/a | yes |
| cidr_block | Primary IPv4 CIDR block for the VPC. | `string` | n/a | yes |
| availability_zones | Explicit AZ list; auto-selected when empty. | `list(string)` | `[]` | no |
| availability_zone_count | Number of AZs to auto-select when availability_zones is empty. | `number` | `2` | no |
| create_public_subnets | Whether to create public subnets + Internet Gateway. | `bool` | `true` | no |
| create_private_subnets | Whether to create private subnets. | `bool` | `true` | no |
| public_subnet_cidrs | Explicit public subnet CIDRs; auto-derived when empty. | `list(string)` | `[]` | no |
| private_subnet_cidrs | Explicit private subnet CIDRs; auto-derived when empty. | `list(string)` | `[]` | no |
| map_public_ip_on_launch | Auto-assign public IPs in public subnets. | `bool` | `false` | no |
| enable_dns_support | Enable DNS resolution in the VPC. | `bool` | `true` | no |
| enable_dns_hostnames | Enable DNS hostnames for public IPs. | `bool` | `true` | no |
| instance_tenancy | `default` or `dedicated`. | `string` | `"default"` | no |
| nat_gateway_strategy | `single`, `one_per_az`, or `none`. | `string` | `"single"` | no |
| enable_flow_logs | Create a VPC Flow Log. | `bool` | `false` | no |
| flow_log_destination_arn | CloudWatch Log Group or S3 bucket ARN. Required if enable_flow_logs. | `string` | `null` | no |
| flow_log_traffic_type | `ACCEPT`, `REJECT`, or `ALL`. | `string` | `"ALL"` | no |
| flow_log_iam_role_arn | IAM role ARN for CloudWatch destination flow logs. | `string` | `null` | no |
| manage_public_network_acl | Create a custom NACL for public subnets (deny-all if rules empty). | `bool` | `false` | no |
| public_network_acl_ingress_rules | Ingress rules for the public NACL. | `list(object(...))` | `[]` | no |
| public_network_acl_egress_rules | Egress rules for the public NACL. | `list(object(...))` | `[]` | no |
| manage_private_network_acl | Create a custom NACL for private subnets (deny-all if rules empty). | `bool` | `false` | no |
| private_network_acl_ingress_rules | Ingress rules for the private NACL. | `list(object(...))` | `[]` | no |
| private_network_acl_egress_rules | Egress rules for the private NACL. | `list(object(...))` | `[]` | no |
| tags | Tags merged onto every resource. Put Owner/CostCenter etc. here. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC. |
| vpc_cidr_block | Primary IPv4 CIDR block of the VPC. |
| vpc_arn | ARN of the VPC. |
| availability_zones | AZs actually used (explicit or auto-selected). |
| internet_gateway_id | Internet Gateway ID, or null. |
| public_subnet_ids | Map of AZ => public subnet ID. |
| private_subnet_ids | Map of AZ => private subnet ID. |
| public_route_table_id | Shared public route table ID, or null. |
| private_route_table_ids | Map of AZ => private route table ID. |
| nat_gateway_ids | Map of AZ => NAT Gateway ID (empty if strategy = none). |
| nat_gateway_public_ips | Map of AZ => NAT Gateway EIP (empty if strategy = none). |
| public_network_acl_id | Custom public NACL ID, or null. |
| private_network_acl_id | Custom private NACL ID, or null. |
| flow_log_id | VPC Flow Log ID, or null. |
<!-- END_TF_DOCS -->
