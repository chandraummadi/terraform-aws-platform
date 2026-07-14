# vpc

Full-feature-parity VPC module: public/private/database/elasticache/
redshift/intra/outpost subnet tiers, IPv6 dual-stack, secondary CIDR blocks
and IPAM pool sourcing, DHCP options, NAT Gateway (single / one-per-AZ /
none / reused EIPs), egress-only IGW, VPN Gateway + Customer Gateways,
per-tier custom Network ACLs, default VPC/SG/NACL/route-table management,
and VPC Flow Logs (self-contained CloudWatch Log Group + scoped IAM role by
default, or bring-your-own destination). Every tier beyond
public/private is opt-in (`false` by default) — the common case still needs
only 3 required variables.

## Design notes

**NAT Gateway and NACLs are inline, not child modules.** Neither is
independently versioned or ever called directly by a consumer — only this
top-level module gets a semver tag (`vpc/vX.Y.Z`, per
`docs/coding-standards.md` §6). A submodule boundary here would add a second
place to read when tracing NAT/route logic and a second terraform-docs
table to keep in sync, with no consumer-facing benefit in return.

**Ported from `terraform-aws-modules/terraform-aws-vpc`'s feature set, not
its code style.** That module (the de facto community standard for this
exact use case) is the reference for *what AWS capabilities to expose* —
every subnet tier, IPv6, IPAM, VPN/Customer Gateway, and default-resource
management it supports, this module also supports. But its implementation
leans on `count` + `element()`/`lookup()` throughout, which is exactly the
"insert-in-the-middle reshuffles every subsequent resource" footgun
`docs/coding-standards.md` §9 mandates avoiding, and loosely-typed
`list(any)` rule objects where §3 mandates typed `object()` with
`optional()` attributes. Every resource here is `for_each`-keyed by a
stable value (AZ name, or a logical map key) instead, and every rule/gateway
input is a real typed object — same capability, safer refactor surface.

**Scope trims from the reference, deliberately:** per-AZ tag overrides
(`*_tags_per_az`) and per-subnet name-override arrays are cosmetic
tag-string plumbing, not AWS capability, and were left out to keep the
variable count reviewable. `create_vpc` (a toggle to skip creating the VPC
resource entirely) was dropped too — every real consumer calling this
module wants a VPC; if you don't, don't call the module.

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
- **Operational excellence pillar**: flow logs are self-contained by
  default — this module creates its own CloudWatch Log Group and a
  least-privilege IAM role scoped to just that Log Group's ARN (never
  `Resource = "*"`). Set `create_flow_log_cloudwatch_log_group = false`
  and/or `create_flow_log_cloudwatch_iam_role = false` to bring your own
  destination instead (e.g. to centralize many VPCs' flow logs into one
  Log Group the `cloudwatch`/`iam` modules own).

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

  enable_flow_logs = true
  # That's it for the common case — this module creates its own CloudWatch
  # Log Group + scoped IAM role. To centralize into an existing Log Group
  # instead: set create_flow_log_cloudwatch_log_group = false and pass
  # flow_log_destination_arn = module.cloudwatch.log_group_arn (and
  # likewise create_flow_log_cloudwatch_iam_role = false + flow_log_iam_role_arn).

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

<!--
  STALE PLACEHOLDER — DO NOT MERGE AS-IS.

  This block held a hand-authored approximation of the terraform-docs
  output back when the module had ~30 variables. After the full-parity
  expansion (117 variables, 7 subnet tiers, ~15 child resource types) hand-
  maintaining this table by eyeball is exactly the kind of drift
  terraform-docs exists to prevent, so it's deliberately left as this
  notice instead of a table that would go stale the moment anyone touches
  main.tf/variables.tf again.

  Before merging, run for real:
    terraform-docs markdown table --output-file README.md --output-mode inject .
  from inside modules/vpc/, which will replace this comment block with an
  accurate, complete Requirements / Providers / Resources / Inputs /
  Outputs table generated directly from the .tf files — the Definition of
  Done in docs/coding-standards.md §10 requires this before merge anyway.
-->

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.50 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_customer_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_default_network_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl) | resource |
| [aws_default_route_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_egress_only_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/egress_only_internet_gateway) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_elasticache_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_policy.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_network_acl.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.elasticache](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_redshift_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/redshift_subnet_group) | resource |
| [aws_route.database_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.database_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.elasticache_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_ipv6_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.elasticache](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.redshift](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.elasticache](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.outpost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.redshift](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.elasticache](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.outpost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.redshift](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_block_public_access_options.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_block_public_access_options) | resource |
| [aws_vpc_dhcp_options.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_dhcp_options) | resource |
| [aws_vpc_dhcp_options_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_dhcp_options_association) | resource |
| [aws_vpc_ipv4_cidr_block_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway) | resource |
| [aws_vpn_gateway_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_attachment) | resource |
| [aws_vpn_gateway_route_propagation.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_vpn_gateway_route_propagation.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_vpn_gateway_route_propagation.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.flow_log_cloudwatch_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_amazon_side_asn"></a> [amazon\_side\_asn](#input\_amazon\_side\_asn) | Amazon side ASN for the VPN Gateway this module creates. Only used when enable\_vpn\_gateway = true. | `string` | `"64512"` | no |
| <a name="input_availability_zone_count"></a> [availability\_zone\_count](#input\_availability\_zone\_count) | Number of AZs to auto-select when availability\_zones is not supplied. Ignored if availability\_zones is non-empty. | `number` | `2` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Explicit list of AZs to use. If empty (the default), the module selects the first availability\_zone\_count AZs (alphabetically) returned by the aws\_availability\_zones data source. | `list(string)` | `[]` | no |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | Primary IPv4 CIDR block for the VPC (e.g. "10.20.0.0/16"). Leave as "" only when use\_ipam\_pool = true (the pool supplies the CIDR instead). Subnet CIDRs are auto-derived from this block unless the per-tier *\_subnet\_cidrs variables are explicitly supplied. | `string` | n/a | yes |
| <a name="input_create_database_internet_gateway_route"></a> [create\_database\_internet\_gateway\_route](#input\_create\_database\_internet\_gateway\_route) | Whether database subnets get a route to the Internet Gateway. Secure default is false — database subnets should stay off the public path; only enable for a documented exception (e.g. a publicly reachable RDS instance you've explicitly decided you need, per README "Public access to RDS" note). | `bool` | `false` | no |
| <a name="input_create_database_nat_gateway_route"></a> [create\_database\_nat\_gateway\_route](#input\_create\_database\_nat\_gateway\_route) | Whether database subnets route outbound traffic through the shared NAT Gateway(s). Ignored if create\_database\_internet\_gateway\_route = true. | `bool` | `true` | no |
| <a name="input_create_database_subnet_group"></a> [create\_database\_subnet\_group](#input\_create\_database\_subnet\_group) | Whether to create an aws\_db\_subnet\_group spanning the database subnets. | `bool` | `true` | no |
| <a name="input_create_database_subnets"></a> [create\_database\_subnets](#input\_create\_database\_subnets) | Whether to create a dedicated database subnet tier, isolated from the general-purpose private subnets. | `bool` | `false` | no |
| <a name="input_create_egress_only_igw"></a> [create\_egress\_only\_igw](#input\_create\_egress\_only\_igw) | Whether to create an Egress-Only Internet Gateway for IPv6 outbound-only routing from private-tier subnets. Only takes effect when enable\_ipv6 = true. | `bool` | `true` | no |
| <a name="input_create_elasticache_subnet_group"></a> [create\_elasticache\_subnet\_group](#input\_create\_elasticache\_subnet\_group) | Whether to create an aws\_elasticache\_subnet\_group spanning the ElastiCache subnets. | `bool` | `true` | no |
| <a name="input_create_elasticache_subnets"></a> [create\_elasticache\_subnets](#input\_create\_elasticache\_subnets) | Whether to create a dedicated ElastiCache subnet tier. | `bool` | `false` | no |
| <a name="input_create_flow_log_cloudwatch_iam_role"></a> [create\_flow\_log\_cloudwatch\_iam\_role](#input\_create\_flow\_log\_cloudwatch\_iam\_role) | Whether this module creates a least-privilege IAM role + policy (scoped to only the flow log's own Log Group ARN, never Resource = "*") for the flow log service to assume. Only relevant when flow\_log\_destination\_type = "cloud-watch-logs". Set false and supply flow\_log\_iam\_role\_arn to bring your own. | `bool` | `true` | no |
| <a name="input_create_flow_log_cloudwatch_log_group"></a> [create\_flow\_log\_cloudwatch\_log\_group](#input\_create\_flow\_log\_cloudwatch\_log\_group) | Whether this module creates its own CloudWatch Log Group for flow logs. Only relevant when flow\_log\_destination\_type = "cloud-watch-logs". Set false and supply flow\_log\_destination\_arn to bring your own (e.g. a centralized Log Group owned by the cloudwatch module). | `bool` | `true` | no |
| <a name="input_create_intra_subnets"></a> [create\_intra\_subnets](#input\_create\_intra\_subnets) | Whether to create "intra" subnets — subnets with no route to a NAT Gateway or Internet Gateway at all. Useful for workloads (e.g. Lambda-in-VPC reaching only internal resources / VPC endpoints) that should have zero internet path, not even outbound. | `bool` | `false` | no |
| <a name="input_create_multiple_intra_route_tables"></a> [create\_multiple\_intra\_route\_tables](#input\_create\_multiple\_intra\_route\_tables) | If true, create one intra route table per AZ instead of one shared table. | `bool` | `false` | no |
| <a name="input_create_multiple_public_route_tables"></a> [create\_multiple\_public\_route\_tables](#input\_create\_multiple\_public\_route\_tables) | If true, create one public route table per AZ instead of one shared table. Only useful if you plan to diverge routes per AZ later (e.g. per-AZ NAT for outbound-only egress mixed with a shared IGW route) — most consumers should leave this false. | `bool` | `false` | no |
| <a name="input_create_outpost_subnets"></a> [create\_outpost\_subnets](#input\_create\_outpost\_subnets) | Whether to create subnets on an AWS Outpost. Niche — only relevant if you operate Outposts hardware. | `bool` | `false` | no |
| <a name="input_create_private_subnets"></a> [create\_private\_subnets](#input\_create\_private\_subnets) | Whether to create private subnets. | `bool` | `true` | no |
| <a name="input_create_public_subnets"></a> [create\_public\_subnets](#input\_create\_public\_subnets) | Whether to create public subnets (and the Internet Gateway + public route table they need). | `bool` | `true` | no |
| <a name="input_create_redshift_subnet_group"></a> [create\_redshift\_subnet\_group](#input\_create\_redshift\_subnet\_group) | Whether to create an aws\_redshift\_subnet\_group spanning the Redshift subnets. | `bool` | `true` | no |
| <a name="input_create_redshift_subnets"></a> [create\_redshift\_subnets](#input\_create\_redshift\_subnets) | Whether to create a dedicated Redshift subnet tier. Niche — most consumers should use database\_subnets for Redshift too; only enable this if you need Redshift on genuinely separate subnets/route table from RDS. | `bool` | `false` | no |
| <a name="input_customer_gateways"></a> [customer\_gateways](#input\_customer\_gateways) | Map (keyed by a logical name you choose) of Customer Gateways to create for site-to-site VPN. | <pre>map(object({<br/>    bgp_asn     = number<br/>    ip_address  = string<br/>    device_name = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_customer_owned_ipv4_pool"></a> [customer\_owned\_ipv4\_pool](#input\_customer\_owned\_ipv4\_pool) | Customer-owned IPv4 address pool for the Outpost subnet, if using CoIP. | `string` | `null` | no |
| <a name="input_database_network_acl_egress_rules"></a> [database\_network\_acl\_egress\_rules](#input\_database\_network\_acl\_egress\_rules) | Egress rules for the database subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_database_network_acl_ingress_rules"></a> [database\_network\_acl\_ingress\_rules](#input\_database\_network\_acl\_ingress\_rules) | Ingress rules for the database subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_database_subnet_cidrs"></a> [database\_subnet\_cidrs](#input\_database\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for database subnets, one per AZ. Auto-derived from cidr\_block when empty. | `list(string)` | `[]` | no |
| <a name="input_database_subnet_group_name"></a> [database\_subnet\_group\_name](#input\_database\_subnet\_group\_name) | Name for the DB subnet group. Defaults to name\_prefix when null. | `string` | `null` | no |
| <a name="input_default_network_acl_egress"></a> [default\_network\_acl\_egress](#input\_default\_network\_acl\_egress) | Egress rules for the managed default NACL. Only used when manage\_default\_network\_acl = true. | <pre>list(object({<br/>    rule_no         = number<br/>    action          = string<br/>    protocol        = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_default_network_acl_ingress"></a> [default\_network\_acl\_ingress](#input\_default\_network\_acl\_ingress) | Ingress rules for the managed default NACL. Only used when manage\_default\_network\_acl = true. | <pre>list(object({<br/>    rule_no         = number<br/>    action          = string<br/>    protocol        = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_default_route_table_routes"></a> [default\_route\_table\_routes](#input\_default\_route\_table\_routes) | Routes for the managed default route table. Only used when manage\_default\_route\_table = true. | <pre>list(object({<br/>    cidr_block                = optional(string)<br/>    ipv6_cidr_block           = optional(string)<br/>    gateway_id                = optional(string)<br/>    nat_gateway_id            = optional(string)<br/>    vpc_peering_connection_id = optional(string)<br/>    transit_gateway_id        = optional(string)<br/>    vpc_endpoint_id           = optional(string)<br/>    egress_only_gateway_id    = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_egress"></a> [default\_security\_group\_egress](#input\_default\_security\_group\_egress) | Egress rules for the managed default security group. Empty (the default) means deny-all outbound. Only used when manage\_default\_security\_group = true. | <pre>list(object({<br/>    description     = optional(string)<br/>    self            = optional(bool)<br/>    cidr_blocks     = optional(list(string), [])<br/>    security_groups = optional(list(string), [])<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    protocol        = optional(string, "-1")<br/>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_ingress"></a> [default\_security\_group\_ingress](#input\_default\_security\_group\_ingress) | Ingress rules for the managed default security group. Empty (the default) means deny-all inbound. Only used when manage\_default\_security\_group = true. | <pre>list(object({<br/>    description     = optional(string)<br/>    self            = optional(bool)<br/>    cidr_blocks     = optional(list(string), [])<br/>    security_groups = optional(list(string), [])<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    protocol        = optional(string, "-1")<br/>  }))</pre> | `[]` | no |
| <a name="input_dhcp_options_domain_name"></a> [dhcp\_options\_domain\_name](#input\_dhcp\_options\_domain\_name) | Domain name for the DHCP Options Set. Only used when enable\_dhcp\_options = true. | `string` | `null` | no |
| <a name="input_dhcp_options_domain_name_servers"></a> [dhcp\_options\_domain\_name\_servers](#input\_dhcp\_options\_domain\_name\_servers) | Domain name servers for the DHCP Options Set. | `list(string)` | <pre>[<br/>  "AmazonProvidedDNS"<br/>]</pre> | no |
| <a name="input_dhcp_options_ntp_servers"></a> [dhcp\_options\_ntp\_servers](#input\_dhcp\_options\_ntp\_servers) | NTP servers for the DHCP Options Set. | `list(string)` | `[]` | no |
| <a name="input_elasticache_network_acl_egress_rules"></a> [elasticache\_network\_acl\_egress\_rules](#input\_elasticache\_network\_acl\_egress\_rules) | Egress rules for the ElastiCache subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_elasticache_network_acl_ingress_rules"></a> [elasticache\_network\_acl\_ingress\_rules](#input\_elasticache\_network\_acl\_ingress\_rules) | Ingress rules for the ElastiCache subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_elasticache_subnet_cidrs"></a> [elasticache\_subnet\_cidrs](#input\_elasticache\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for ElastiCache subnets, one per AZ. Auto-derived from cidr\_block when empty. | `list(string)` | `[]` | no |
| <a name="input_elasticache_subnet_group_name"></a> [elasticache\_subnet\_group\_name](#input\_elasticache\_subnet\_group\_name) | Name for the ElastiCache subnet group. Defaults to name\_prefix when null. | `string` | `null` | no |
| <a name="input_enable_dhcp_options"></a> [enable\_dhcp\_options](#input\_enable\_dhcp\_options) | Whether to create and associate a custom DHCP Options Set. When false, the VPC uses the AWS-managed default (AmazonProvidedDNS). | `bool` | `false` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Whether instances with public IPs get corresponding public DNS hostnames. | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Whether DNS resolution is supported within the VPC. | `bool` | `true` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Whether to create a VPC Flow Log. | `bool` | `false` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Whether to provision an IPv6 CIDR alongside IPv4 and enable dual-stack subnets. When true, every subnet tier gets an auto-derived /64 IPv6 CIDR carved from the VPC's /56 (via cidrsubnet), same indexing scheme as the IPv4 auto-derivation. | `bool` | `false` | no |
| <a name="input_enable_network_address_usage_metrics"></a> [enable\_network\_address\_usage\_metrics](#input\_enable\_network\_address\_usage\_metrics) | Whether to enable Network Address Usage metrics for the VPC. | `bool` | `false` | no |
| <a name="input_enable_public_redshift"></a> [enable\_public\_redshift](#input\_enable\_public\_redshift) | Whether Redshift subnets associate with the public route table instead of a private/NAT one. Secure default is false. | `bool` | `false` | no |
| <a name="input_enable_vpn_gateway"></a> [enable\_vpn\_gateway](#input\_enable\_vpn\_gateway) | Whether to create and attach an aws\_vpn\_gateway to this VPC. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Used in local.common\_tags. | `string` | n/a | yes |
| <a name="input_external_nat_ip_ids"></a> [external\_nat\_ip\_ids](#input\_external\_nat\_ip\_ids) | Pre-allocated EIP allocation IDs to reuse for NAT Gateways. Required (and must have as many entries as NAT Gateways created) when reuse\_nat\_ips = true. | `list(string)` | `[]` | no |
| <a name="input_flow_log_cloudwatch_iam_role_conditions"></a> [flow\_log\_cloudwatch\_iam\_role\_conditions](#input\_flow\_log\_cloudwatch\_iam\_role\_conditions) | Extra IAM assume-role policy conditions for the auto-created role (e.g. sts:ExternalId for cross-account delivery). | <pre>list(object({<br/>    test     = string<br/>    variable = string<br/>    values   = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_flow_log_cloudwatch_log_group_class"></a> [flow\_log\_cloudwatch\_log\_group\_class](#input\_flow\_log\_cloudwatch\_log\_group\_class) | Log Group class: "STANDARD" or "INFREQUENT\_ACCESS". | `string` | `"STANDARD"` | no |
| <a name="input_flow_log_cloudwatch_log_group_kms_key_id"></a> [flow\_log\_cloudwatch\_log\_group\_kms\_key\_id](#input\_flow\_log\_cloudwatch\_log\_group\_kms\_key\_id) | KMS key ARN to encrypt the auto-created Log Group with. Leave null to use CloudWatch Logs' default encryption. | `string` | `null` | no |
| <a name="input_flow_log_cloudwatch_log_group_name_prefix"></a> [flow\_log\_cloudwatch\_log\_group\_name\_prefix](#input\_flow\_log\_cloudwatch\_log\_group\_name\_prefix) | Prefix for the auto-created Log Group's name. | `string` | `"/aws/vpc-flow-log/"` | no |
| <a name="input_flow_log_cloudwatch_log_group_name_suffix"></a> [flow\_log\_cloudwatch\_log\_group\_name\_suffix](#input\_flow\_log\_cloudwatch\_log\_group\_name\_suffix) | Suffix for the auto-created Log Group's name. Defaults to the VPC ID when left empty. | `string` | `""` | no |
| <a name="input_flow_log_cloudwatch_log_group_retention_in_days"></a> [flow\_log\_cloudwatch\_log\_group\_retention\_in\_days](#input\_flow\_log\_cloudwatch\_log\_group\_retention\_in\_days) | Retention period for the auto-created Log Group. | `number` | `365` | no |
| <a name="input_flow_log_cloudwatch_log_group_skip_destroy"></a> [flow\_log\_cloudwatch\_log\_group\_skip\_destroy](#input\_flow\_log\_cloudwatch\_log\_group\_skip\_destroy) | Whether to keep the Log Group on destroy (skips deleting existing log data when the VPC is torn down). | `bool` | `false` | no |
| <a name="input_flow_log_deliver_cross_account_role"></a> [flow\_log\_deliver\_cross\_account\_role](#input\_flow\_log\_deliver\_cross\_account\_role) | IAM role ARN used when the flow log destination lives in a different account than this VPC. Leave null for same-account delivery. | `string` | `null` | no |
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of an existing CloudWatch Log Group or S3 bucket to deliver flow logs to. Required when the corresponding create\_flow\_log\_cloudwatch\_log\_group is false (bring-your-own mode) or when flow\_log\_destination\_type = "s3" (this module never creates an S3 bucket). Ignored (self-contained mode) when destination\_type = "cloud-watch-logs" and create\_flow\_log\_cloudwatch\_log\_group = true. | `string` | `null` | no |
| <a name="input_flow_log_destination_type"></a> [flow\_log\_destination\_type](#input\_flow\_log\_destination\_type) | Where flow logs are delivered: "cloud-watch-logs" or "s3". | `string` | `"cloud-watch-logs"` | no |
| <a name="input_flow_log_file_format"></a> [flow\_log\_file\_format](#input\_flow\_log\_file\_format) | File format for flow logs delivered to S3. | `string` | `"plain-text"` | no |
| <a name="input_flow_log_hive_compatible_partitions"></a> [flow\_log\_hive\_compatible\_partitions](#input\_flow\_log\_hive\_compatible\_partitions) | Whether S3-delivered flow logs use Hive-compatible S3 prefixes. | `bool` | `false` | no |
| <a name="input_flow_log_iam_role_arn"></a> [flow\_log\_iam\_role\_arn](#input\_flow\_log\_iam\_role\_arn) | Existing IAM role ARN for the flow log service to assume. Required when create\_flow\_log\_cloudwatch\_iam\_role = false and flow\_log\_destination\_type = "cloud-watch-logs". | `string` | `null` | no |
| <a name="input_flow_log_log_format"></a> [flow\_log\_log\_format](#input\_flow\_log\_log\_format) | Custom flow log record format. Leave null for the AWS default field set. | `string` | `null` | no |
| <a name="input_flow_log_max_aggregation_interval"></a> [flow\_log\_max\_aggregation\_interval](#input\_flow\_log\_max\_aggregation\_interval) | Maximum interval (seconds) at which flow log records are captured. | `number` | `600` | no |
| <a name="input_flow_log_per_hour_partition"></a> [flow\_log\_per\_hour\_partition](#input\_flow\_log\_per\_hour\_partition) | Whether S3-delivered flow logs are additionally partitioned by hour. | `bool` | `false` | no |
| <a name="input_flow_log_traffic_type"></a> [flow\_log\_traffic\_type](#input\_flow\_log\_traffic\_type) | Type of traffic to capture in the flow log. | `string` | `"ALL"` | no |
| <a name="input_instance_tenancy"></a> [instance\_tenancy](#input\_instance\_tenancy) | Tenancy of instances launched into the VPC by default. | `string` | `"default"` | no |
| <a name="input_intra_network_acl_egress_rules"></a> [intra\_network\_acl\_egress\_rules](#input\_intra\_network\_acl\_egress\_rules) | Egress rules for the intra subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_intra_network_acl_ingress_rules"></a> [intra\_network\_acl\_ingress\_rules](#input\_intra\_network\_acl\_ingress\_rules) | Ingress rules for the intra subnets' NACL. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_intra_subnet_cidrs"></a> [intra\_subnet\_cidrs](#input\_intra\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for intra subnets, one per AZ. Auto-derived from cidr\_block when empty. | `list(string)` | `[]` | no |
| <a name="input_ipv4_ipam_pool_id"></a> [ipv4\_ipam\_pool\_id](#input\_ipv4\_ipam\_pool\_id) | IPAM pool ID to source the VPC's primary IPv4 CIDR from. Required when use\_ipam\_pool = true. | `string` | `null` | no |
| <a name="input_ipv4_netmask_length"></a> [ipv4\_netmask\_length](#input\_ipv4\_netmask\_length) | Netmask length to request from ipv4\_ipam\_pool\_id when cidr\_block is left as "". Ignored if cidr\_block is a real CIDR. | `number` | `null` | no |
| <a name="input_ipv6_ipam_pool_id"></a> [ipv6\_ipam\_pool\_id](#input\_ipv6\_ipam\_pool\_id) | IPAM pool ID to source the VPC's IPv6 CIDR from. If null and enable\_ipv6 = true, AWS assigns an Amazon-provided /56. | `string` | `null` | no |
| <a name="input_ipv6_netmask_length"></a> [ipv6\_netmask\_length](#input\_ipv6\_netmask\_length) | Netmask length to request from ipv6\_ipam\_pool\_id. Ignored if ipv6\_ipam\_pool\_id is null. | `number` | `null` | no |
| <a name="input_manage_database_network_acl"></a> [manage\_database\_network\_acl](#input\_manage\_database\_network\_acl) | Create a custom NACL for database subnets. Deny-all if the rule lists are left empty. Only applies when create\_database\_subnets = true. | `bool` | `false` | no |
| <a name="input_manage_default_network_acl"></a> [manage\_default\_network\_acl](#input\_manage\_default\_network\_acl) | Whether to manage this VPC's default network ACL (the one AWS auto-creates, distinct from the per-tier custom NACLs this module can also create). Only used to explicitly lock down or document the default NACL's rules; leave false to not touch it. | `bool` | `false` | no |
| <a name="input_manage_default_route_table"></a> [manage\_default\_route\_table](#input\_manage\_default\_route\_table) | Whether to manage this VPC's default route table (distinct from the public/private/etc. route tables this module creates explicitly). Only used when you need to document/control what's in the AWS-auto-created default; leave false otherwise. | `bool` | `false` | no |
| <a name="input_manage_default_security_group"></a> [manage\_default\_security\_group](#input\_manage\_default\_security\_group) | Whether to manage this VPC's default security group and lock it to deny-all (empty ingress/egress rule lists). Defaults to true — AWS's own default security group allows all traffic between members and all egress, which this module treats as a real security gap (checkov CKV2\_AWS\_12), not an acceptable AWS-managed default to leave alone. Set false only if something else in your account already manages this VPC's default SG and you don't want two owners fighting over it. | `bool` | `true` | no |
| <a name="input_manage_elasticache_network_acl"></a> [manage\_elasticache\_network\_acl](#input\_manage\_elasticache\_network\_acl) | Create a custom NACL for ElastiCache subnets. Only applies when create\_elasticache\_subnets = true. | `bool` | `false` | no |
| <a name="input_manage_intra_network_acl"></a> [manage\_intra\_network\_acl](#input\_manage\_intra\_network\_acl) | Create a custom NACL for intra subnets. Only applies when create\_intra\_subnets = true. | `bool` | `false` | no |
| <a name="input_manage_private_network_acl"></a> [manage\_private\_network\_acl](#input\_manage\_private\_network\_acl) | Create a custom NACL for private subnets. Deny-all if the rule lists are left empty. | `bool` | `false` | no |
| <a name="input_manage_public_network_acl"></a> [manage\_public\_network\_acl](#input\_manage\_public\_network\_acl) | Create a custom NACL for public subnets. Deny-all if the rule lists are left empty. | `bool` | `false` | no |
| <a name="input_map_customer_owned_ip_on_launch"></a> [map\_customer\_owned\_ip\_on\_launch](#input\_map\_customer\_owned\_ip\_on\_launch) | Whether instances launched into the Outpost subnet auto-assign a customer-owned IP. | `bool` | `false` | no |
| <a name="input_map_public_ip_on_launch"></a> [map\_public\_ip\_on\_launch](#input\_map\_public\_ip\_on\_launch) | Whether instances launched into public subnets automatically receive a public IP. Defaults to false (secure default). | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name identifier for this VPC, used as the resource name prefix (e.g. "payments-prod"). | `string` | n/a | yes |
| <a name="input_nat_gateway_destination_cidr_block"></a> [nat\_gateway\_destination\_cidr\_block](#input\_nat\_gateway\_destination\_cidr\_block) | Destination CIDR for the private-subnet NAT route. Override only for split-tunnel/overlapping-CIDR scenarios; almost always leave this as the default. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_nat_gateway_strategy"></a> [nat\_gateway\_strategy](#input\_nat\_gateway\_strategy) | How private (and, if enabled, database/elasticache/redshift) subnets reach the internet: "single" (one NAT Gateway shared across all AZs), "one\_per\_az" (one per AZ, full HA), or "none" (no NAT Gateway). | `string` | `"single"` | no |
| <a name="input_outpost_arn"></a> [outpost\_arn](#input\_outpost\_arn) | ARN of the Outpost to place subnets on. Required when create\_outpost\_subnets = true. | `string` | `null` | no |
| <a name="input_outpost_az"></a> [outpost\_az](#input\_outpost\_az) | Availability zone the Outpost is homed to. Required when create\_outpost\_subnets = true. | `string` | `null` | no |
| <a name="input_outpost_subnet_cidrs"></a> [outpost\_subnet\_cidrs](#input\_outpost\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for Outpost subnets. Required when create\_outpost\_subnets = true (no AZ list to auto-derive an index from, since Outposts are single-AZ). | `list(string)` | `[]` | no |
| <a name="input_private_network_acl_egress_rules"></a> [private\_network\_acl\_egress\_rules](#input\_private\_network\_acl\_egress\_rules) | Egress rules for the private subnets' NACL. Only used when manage\_private\_network\_acl = true. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_private_network_acl_ingress_rules"></a> [private\_network\_acl\_ingress\_rules](#input\_private\_network\_acl\_ingress\_rules) | Ingress rules for the private subnets' NACL. Only used when manage\_private\_network\_acl = true. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for private subnets, one per AZ. If empty and create\_private\_subnets = true, auto-derived from cidr\_block via cidrsubnet(). | `list(string)` | `[]` | no |
| <a name="input_propagate_intra_route_tables_vgw"></a> [propagate\_intra\_route\_tables\_vgw](#input\_propagate\_intra\_route\_tables\_vgw) | Whether to propagate VPN Gateway routes into the intra route table(s). | `bool` | `false` | no |
| <a name="input_propagate_private_route_tables_vgw"></a> [propagate\_private\_route\_tables\_vgw](#input\_propagate\_private\_route\_tables\_vgw) | Whether to propagate VPN Gateway routes into the private route table(s). | `bool` | `false` | no |
| <a name="input_propagate_public_route_tables_vgw"></a> [propagate\_public\_route\_tables\_vgw](#input\_propagate\_public\_route\_tables\_vgw) | Whether to propagate VPN Gateway routes into the public route table(s). | `bool` | `false` | no |
| <a name="input_public_network_acl_egress_rules"></a> [public\_network\_acl\_egress\_rules](#input\_public\_network\_acl\_egress\_rules) | Egress rules for the public subnets' NACL. Only used when manage\_public\_network\_acl = true. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_public_network_acl_ingress_rules"></a> [public\_network\_acl\_ingress\_rules](#input\_public\_network\_acl\_ingress\_rules) | Ingress rules for the public subnets' NACL. Only used when manage\_public\_network\_acl = true. | <pre>list(object({<br/>    rule_number     = number<br/>    protocol        = string<br/>    rule_action     = string<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for public subnets, one per AZ. If empty and create\_public\_subnets = true, auto-derived from cidr\_block via cidrsubnet(). | `list(string)` | `[]` | no |
| <a name="input_redshift_subnet_cidrs"></a> [redshift\_subnet\_cidrs](#input\_redshift\_subnet\_cidrs) | Explicit IPv4 CIDR blocks for Redshift subnets, one per AZ. Auto-derived from cidr\_block when empty. | `list(string)` | `[]` | no |
| <a name="input_redshift_subnet_group_name"></a> [redshift\_subnet\_group\_name](#input\_redshift\_subnet\_group\_name) | Name for the Redshift subnet group. Defaults to name\_prefix when null. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region override applied to every resource in this module via the provider's per-resource `region` argument (AWS provider >= 5.100). Leave null to use the provider's configured region — this is an override for multi-region-from-one-provider setups, not a required input. | `string` | `null` | no |
| <a name="input_reuse_nat_ips"></a> [reuse\_nat\_ips](#input\_reuse\_nat\_ips) | If true, attach the Elastic IPs in external\_nat\_ip\_ids to the NAT Gateway(s) instead of allocating new ones. Useful when downstream firewalls/allowlists are pinned to specific, already-known IPs. | `bool` | `false` | no |
| <a name="input_secondary_cidr_blocks"></a> [secondary\_cidr\_blocks](#input\_secondary\_cidr\_blocks) | Additional IPv4 CIDR blocks to associate with the VPC beyond the primary cidr\_block. Each gets its own aws\_vpc\_ipv4\_cidr\_block\_association. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource this module creates, merged with module-computed tags (Environment, ManagedBy, Module). Ownership metadata (Owner, CostCenter, etc.) belongs here — see docs/coding-standards.md §4 — this module deliberately has no dedicated owner variable. | `map(string)` | `{}` | no |
| <a name="input_use_ipam_pool"></a> [use\_ipam\_pool](#input\_use\_ipam\_pool) | Source the VPC's primary CIDR from an IPAM pool instead of cidr\_block. When true, set ipv4\_ipam\_pool\_id and either cidr\_block (as a pre-allocated CIDR) or ipv4\_netmask\_length. | `bool` | `false` | no |
| <a name="input_vpc_block_public_access_options"></a> [vpc\_block\_public\_access\_options](#input\_vpc\_block\_public\_access\_options) | If set, creates an aws\_vpc\_block\_public\_access\_options resource. This is an ACCOUNT+REGION level setting, not scoped to this one VPC — only set this from a module instance you intend as the source of truth for that account/region. internet\_gateway\_block\_mode: "off", "block-bidirectional", or "block-ingress". | <pre>object({<br/>    internet_gateway_block_mode = string<br/>  })</pre> | `null` | no |
| <a name="input_vpc_flow_log_iam_policy_name"></a> [vpc\_flow\_log\_iam\_policy\_name](#input\_vpc\_flow\_log\_iam\_policy\_name) | Name (or name prefix) for the auto-created IAM policy. | `string` | `null` | no |
| <a name="input_vpc_flow_log_iam_policy_use_name_prefix"></a> [vpc\_flow\_log\_iam\_policy\_use\_name\_prefix](#input\_vpc\_flow\_log\_iam\_policy\_use\_name\_prefix) | Whether vpc\_flow\_log\_iam\_policy\_name is used as a name\_prefix instead of an exact name. | `bool` | `true` | no |
| <a name="input_vpc_flow_log_iam_role_name"></a> [vpc\_flow\_log\_iam\_role\_name](#input\_vpc\_flow\_log\_iam\_role\_name) | Name (or name prefix, per vpc\_flow\_log\_iam\_role\_use\_name\_prefix) for the auto-created IAM role. | `string` | `null` | no |
| <a name="input_vpc_flow_log_iam_role_path"></a> [vpc\_flow\_log\_iam\_role\_path](#input\_vpc\_flow\_log\_iam\_role\_path) | IAM path for the auto-created flow log role. | `string` | `"/"` | no |
| <a name="input_vpc_flow_log_iam_role_use_name_prefix"></a> [vpc\_flow\_log\_iam\_role\_use\_name\_prefix](#input\_vpc\_flow\_log\_iam\_role\_use\_name\_prefix) | Whether vpc\_flow\_log\_iam\_role\_name is used as a name\_prefix instead of an exact name. | `bool` | `true` | no |
| <a name="input_vpc_flow_log_permissions_boundary"></a> [vpc\_flow\_log\_permissions\_boundary](#input\_vpc\_flow\_log\_permissions\_boundary) | Permissions boundary ARN to attach to the auto-created flow log IAM role. | `string` | `null` | no |
| <a name="input_vpc_flow_log_tags"></a> [vpc\_flow\_log\_tags](#input\_vpc\_flow\_log\_tags) | Additional tags applied only to flow-log-related resources (the flow log itself, Log Group, IAM role/policy), on top of local.common\_tags. | `map(string)` | `{}` | no |
| <a name="input_vpc_tags"></a> [vpc\_tags](#input\_vpc\_tags) | Additional tags applied only to the aws\_vpc resource, on top of local.common\_tags. | `map(string)` | `{}` | no |
| <a name="input_vpn_gateway_az"></a> [vpn\_gateway\_az](#input\_vpn\_gateway\_az) | Availability zone to create the VPN Gateway in. Leave null to let AWS choose. | `string` | `null` | no |
| <a name="input_vpn_gateway_id"></a> [vpn\_gateway\_id](#input\_vpn\_gateway\_id) | ID of an existing VPN Gateway to attach instead of creating a new one. Mutually exclusive in practice with enable\_vpn\_gateway = true (don't set both). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | Availability zones actually used by this VPC (explicit or auto-selected). |
| <a name="output_customer_gateway_ids"></a> [customer\_gateway\_ids](#output\_customer\_gateway\_ids) | Map of logical name => Customer Gateway ID. |
| <a name="output_database_network_acl_id"></a> [database\_network\_acl\_id](#output\_database\_network\_acl\_id) | ID of the custom database NACL. Null unless manage\_database\_network\_acl = true. |
| <a name="output_database_route_table_ids"></a> [database\_route\_table\_ids](#output\_database\_route\_table\_ids) | Map of route-table key => database route table ID. Empty unless create\_database\_subnets = true. |
| <a name="output_database_subnet_group_name"></a> [database\_subnet\_group\_name](#output\_database\_subnet\_group\_name) | Name of the DB subnet group. Null unless create\_database\_subnets && create\_database\_subnet\_group. |
| <a name="output_database_subnet_ids"></a> [database\_subnet\_ids](#output\_database\_subnet\_ids) | Map of availability zone => database subnet ID. Empty unless create\_database\_subnets = true. |
| <a name="output_default_network_acl_id"></a> [default\_network\_acl\_id](#output\_default\_network\_acl\_id) | ID of the VPC's default network ACL. |
| <a name="output_default_route_table_id"></a> [default\_route\_table\_id](#output\_default\_route\_table\_id) | ID of the VPC's default route table. |
| <a name="output_default_security_group_id"></a> [default\_security\_group\_id](#output\_default\_security\_group\_id) | ID of the VPC's default security group. |
| <a name="output_dhcp_options_id"></a> [dhcp\_options\_id](#output\_dhcp\_options\_id) | ID of the custom DHCP Options Set. Null unless enable\_dhcp\_options = true. |
| <a name="output_egress_only_internet_gateway_id"></a> [egress\_only\_internet\_gateway\_id](#output\_egress\_only\_internet\_gateway\_id) | ID of the Egress-Only Internet Gateway. Null unless enable\_ipv6 && create\_egress\_only\_igw. |
| <a name="output_elasticache_network_acl_id"></a> [elasticache\_network\_acl\_id](#output\_elasticache\_network\_acl\_id) | ID of the custom ElastiCache NACL. Null unless manage\_elasticache\_network\_acl = true. |
| <a name="output_elasticache_subnet_group_name"></a> [elasticache\_subnet\_group\_name](#output\_elasticache\_subnet\_group\_name) | Name of the ElastiCache subnet group. Null unless create\_elasticache\_subnets && create\_elasticache\_subnet\_group. |
| <a name="output_elasticache_subnet_ids"></a> [elasticache\_subnet\_ids](#output\_elasticache\_subnet\_ids) | Map of availability zone => ElastiCache subnet ID. Empty unless create\_elasticache\_subnets = true. |
| <a name="output_flow_log_cloudwatch_log_group_name"></a> [flow\_log\_cloudwatch\_log\_group\_name](#output\_flow\_log\_cloudwatch\_log\_group\_name) | Name of the self-contained CloudWatch Log Group. Null unless create\_flow\_log\_cloudwatch\_log\_group = true (and destination\_type = cloud-watch-logs). |
| <a name="output_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#output\_flow\_log\_destination\_arn) | ARN flow logs are actually delivered to — either the self-contained Log Group this module created, or the bring-your-own destination you supplied. |
| <a name="output_flow_log_iam_role_arn"></a> [flow\_log\_iam\_role\_arn](#output\_flow\_log\_iam\_role\_arn) | ARN of the IAM role flow logs assume to publish. Either the self-contained role this module created, or the bring-your-own role you supplied. |
| <a name="output_flow_log_id"></a> [flow\_log\_id](#output\_flow\_log\_id) | ID of the VPC Flow Log. Null unless enable\_flow\_logs = true. |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | ID of the Internet Gateway. Null when create\_public\_subnets = false. |
| <a name="output_intra_network_acl_id"></a> [intra\_network\_acl\_id](#output\_intra\_network\_acl\_id) | ID of the custom intra NACL. Null unless manage\_intra\_network\_acl = true. |
| <a name="output_intra_route_table_ids"></a> [intra\_route\_table\_ids](#output\_intra\_route\_table\_ids) | Map of route-table key => intra route table ID. Empty unless create\_intra\_subnets = true. |
| <a name="output_intra_subnet_ids"></a> [intra\_subnet\_ids](#output\_intra\_subnet\_ids) | Map of availability zone => intra subnet ID. Empty unless create\_intra\_subnets = true. |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | Map of availability zone => NAT Gateway ID. Empty map when nat\_gateway\_strategy = "none". |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | Map of availability zone => NAT Gateway Elastic IP. Only populated for AWS-allocated EIPs (empty when reuse\_nat\_ips = true — inspect external\_nat\_ip\_ids yourself in that case). |
| <a name="output_outpost_subnet_ids"></a> [outpost\_subnet\_ids](#output\_outpost\_subnet\_ids) | Map of synthetic index key => Outpost subnet ID. Empty unless create\_outpost\_subnets = true. |
| <a name="output_private_network_acl_id"></a> [private\_network\_acl\_id](#output\_private\_network\_acl\_id) | ID of the custom private NACL. Null unless manage\_private\_network\_acl = true. |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Map of availability zone => private route table ID. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Map of availability zone => private subnet ID. |
| <a name="output_public_network_acl_id"></a> [public\_network\_acl\_id](#output\_public\_network\_acl\_id) | ID of the custom public NACL. Null unless manage\_public\_network\_acl = true. |
| <a name="output_public_route_table_ids"></a> [public\_route\_table\_ids](#output\_public\_route\_table\_ids) | Map of route-table key (AZ, or "shared") => public route table ID. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Map of availability zone => public subnet ID. |
| <a name="output_redshift_subnet_group_name"></a> [redshift\_subnet\_group\_name](#output\_redshift\_subnet\_group\_name) | Name of the Redshift subnet group. Null unless create\_redshift\_subnets && create\_redshift\_subnet\_group. |
| <a name="output_redshift_subnet_ids"></a> [redshift\_subnet\_ids](#output\_redshift\_subnet\_ids) | Map of availability zone => Redshift subnet ID. Empty unless create\_redshift\_subnets = true. |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | ARN of the VPC. |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | Primary IPv4 CIDR block of the VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
| <a name="output_vpc_ipv6_cidr_block"></a> [vpc\_ipv6\_cidr\_block](#output\_vpc\_ipv6\_cidr\_block) | IPv6 CIDR block of the VPC. Null unless enable\_ipv6 = true. |
| <a name="output_vpc_secondary_cidr_blocks"></a> [vpc\_secondary\_cidr\_blocks](#output\_vpc\_secondary\_cidr\_blocks) | Additional IPv4 CIDR blocks associated via secondary\_cidr\_blocks. |
| <a name="output_vpn_gateway_id"></a> [vpn\_gateway\_id](#output\_vpn\_gateway\_id) | ID of the VPN Gateway (created or attached-existing). Null unless enable\_vpn\_gateway or vpn\_gateway\_id is set. |
<!-- END_TF_DOCS -->