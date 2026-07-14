## ---------------------------------------------------------------------------
## Required (minimal surface for the common case)
## ---------------------------------------------------------------------------

variable "name" {
  description = "Name identifier for this VPC, used as the resource name prefix (e.g. \"payments-prod\")."
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

variable "cidr_block" {
  description = "Primary IPv4 CIDR block for the VPC (e.g. \"10.20.0.0/16\"). Leave as \"\" only when use_ipam_pool = true (the pool supplies the CIDR instead). Subnet CIDRs are auto-derived from this block unless the per-tier *_subnet_cidrs variables are explicitly supplied."
  type        = string

  validation {
    condition     = var.use_ipam_pool || can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. \"10.20.0.0/16\") unless use_ipam_pool = true."
  }
}

variable "region" {
  description = "AWS region override applied to every resource in this module via the provider's per-resource `region` argument (AWS provider >= 5.100). Leave null to use the provider's configured region — this is an override for multi-region-from-one-provider setups, not a required input."
  type        = string
  default     = null
}

## ---------------------------------------------------------------------------
## Optional — VPC core, secondary CIDR, IPAM, IPv6
## ---------------------------------------------------------------------------

variable "instance_tenancy" {
  description = "Tenancy of instances launched into the VPC by default."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "instance_tenancy must be either \"default\" or \"dedicated\"."
  }
}

variable "enable_dns_support" {
  description = "Whether DNS resolution is supported within the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Whether instances with public IPs get corresponding public DNS hostnames."
  type        = bool
  default     = true
}

variable "enable_network_address_usage_metrics" {
  description = "Whether to enable Network Address Usage metrics for the VPC."
  type        = bool
  default     = false
}

variable "secondary_cidr_blocks" {
  description = "Additional IPv4 CIDR blocks to associate with the VPC beyond the primary cidr_block. Each gets its own aws_vpc_ipv4_cidr_block_association."
  type        = list(string)
  default     = []
}

variable "use_ipam_pool" {
  description = "Source the VPC's primary CIDR from an IPAM pool instead of cidr_block. When true, set ipv4_ipam_pool_id and either cidr_block (as a pre-allocated CIDR) or ipv4_netmask_length."
  type        = bool
  default     = false
}

variable "ipv4_ipam_pool_id" {
  description = "IPAM pool ID to source the VPC's primary IPv4 CIDR from. Required when use_ipam_pool = true."
  type        = string
  default     = null

  validation {
    condition     = !var.use_ipam_pool || var.ipv4_ipam_pool_id != null
    error_message = "ipv4_ipam_pool_id must be set when use_ipam_pool = true."
  }
}

variable "ipv4_netmask_length" {
  description = "Netmask length to request from ipv4_ipam_pool_id when cidr_block is left as \"\". Ignored if cidr_block is a real CIDR."
  type        = number
  default     = null
}

variable "enable_ipv6" {
  description = "Whether to provision an IPv6 CIDR alongside IPv4 and enable dual-stack subnets. When true, every subnet tier gets an auto-derived /64 IPv6 CIDR carved from the VPC's /56 (via cidrsubnet), same indexing scheme as the IPv4 auto-derivation."
  type        = bool
  default     = false
}

variable "ipv6_ipam_pool_id" {
  description = "IPAM pool ID to source the VPC's IPv6 CIDR from. If null and enable_ipv6 = true, AWS assigns an Amazon-provided /56."
  type        = string
  default     = null
}

variable "ipv6_netmask_length" {
  description = "Netmask length to request from ipv6_ipam_pool_id. Ignored if ipv6_ipam_pool_id is null."
  type        = number
  default     = null
}

variable "vpc_tags" {
  description = "Additional tags applied only to the aws_vpc resource, on top of local.common_tags."
  type        = map(string)
  default     = {}
}

## ---------------------------------------------------------------------------
## Optional — VPC Block Public Access (account/region-level control plane)
## ---------------------------------------------------------------------------

variable "vpc_block_public_access_options" {
  description = "If set, creates an aws_vpc_block_public_access_options resource. This is an ACCOUNT+REGION level setting, not scoped to this one VPC — only set this from a module instance you intend as the source of truth for that account/region. internet_gateway_block_mode: \"off\", \"block-bidirectional\", or \"block-ingress\"."
  type = object({
    internet_gateway_block_mode = string
  })
  default = null

  validation {
    condition     = var.vpc_block_public_access_options == null || contains(["off", "block-bidirectional", "block-ingress"], var.vpc_block_public_access_options.internet_gateway_block_mode)
    error_message = "internet_gateway_block_mode must be one of: off, block-bidirectional, block-ingress."
  }
}

## ---------------------------------------------------------------------------
## Optional — DHCP Options Set
## ---------------------------------------------------------------------------

variable "enable_dhcp_options" {
  description = "Whether to create and associate a custom DHCP Options Set. When false, the VPC uses the AWS-managed default (AmazonProvidedDNS)."
  type        = bool
  default     = false
}

variable "dhcp_options_domain_name" {
  description = "Domain name for the DHCP Options Set. Only used when enable_dhcp_options = true."
  type        = string
  default     = null
}

variable "dhcp_options_domain_name_servers" {
  description = "Domain name servers for the DHCP Options Set."
  type        = list(string)
  default     = ["AmazonProvidedDNS"]
}

variable "dhcp_options_ntp_servers" {
  description = "NTP servers for the DHCP Options Set."
  type        = list(string)
  default     = []
}

## ---------------------------------------------------------------------------
## Optional — availability zones
## ---------------------------------------------------------------------------

variable "availability_zones" {
  description = "Explicit list of AZs to use. If empty (the default), the module selects the first availability_zone_count AZs (alphabetically) returned by the aws_availability_zones data source."
  type        = list(string)
  default     = []
}

variable "availability_zone_count" {
  description = "Number of AZs to auto-select when availability_zones is not supplied. Ignored if availability_zones is non-empty."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 6
    error_message = "availability_zone_count must be between 1 and 6."
  }
}

## ---------------------------------------------------------------------------
## Optional — public subnets (on by default)
## ---------------------------------------------------------------------------

variable "create_public_subnets" {
  description = "Whether to create public subnets (and the Internet Gateway + public route table they need)."
  type        = bool
  default     = true
}

variable "public_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for public subnets, one per AZ. If empty and create_public_subnets = true, auto-derived from cidr_block via cidrsubnet()."
  type        = list(string)
  default     = []
}

variable "create_multiple_public_route_tables" {
  description = "If true, create one public route table per AZ instead of one shared table. Only useful if you plan to diverge routes per AZ later (e.g. per-AZ NAT for outbound-only egress mixed with a shared IGW route) — most consumers should leave this false."
  type        = bool
  default     = false
}

variable "map_public_ip_on_launch" {
  description = "Whether instances launched into public subnets automatically receive a public IP. Defaults to false (secure default)."
  type        = bool
  default     = false
}

## ---------------------------------------------------------------------------
## Optional — private subnets (on by default)
## ---------------------------------------------------------------------------

variable "create_private_subnets" {
  description = "Whether to create private subnets."
  type        = bool
  default     = true
}

variable "private_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for private subnets, one per AZ. If empty and create_private_subnets = true, auto-derived from cidr_block via cidrsubnet()."
  type        = list(string)
  default     = []
}

## ---------------------------------------------------------------------------
## Optional — database subnets (opt-in)
## ---------------------------------------------------------------------------

variable "create_database_subnets" {
  description = "Whether to create a dedicated database subnet tier, isolated from the general-purpose private subnets."
  type        = bool
  default     = false
}

variable "database_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for database subnets, one per AZ. Auto-derived from cidr_block when empty."
  type        = list(string)
  default     = []
}

variable "create_database_subnet_group" {
  description = "Whether to create an aws_db_subnet_group spanning the database subnets."
  type        = bool
  default     = true
}

variable "database_subnet_group_name" {
  description = "Name for the DB subnet group. Defaults to name_prefix when null."
  type        = string
  default     = null
}

variable "create_database_internet_gateway_route" {
  description = "Whether database subnets get a route to the Internet Gateway. Secure default is false — database subnets should stay off the public path; only enable for a documented exception (e.g. a publicly reachable RDS instance you've explicitly decided you need, per README \"Public access to RDS\" note)."
  type        = bool
  default     = false
}

variable "create_database_nat_gateway_route" {
  description = "Whether database subnets route outbound traffic through the shared NAT Gateway(s). Ignored if create_database_internet_gateway_route = true."
  type        = bool
  default     = true
}

## ---------------------------------------------------------------------------
## Optional — ElastiCache subnets (opt-in)
## ---------------------------------------------------------------------------

variable "create_elasticache_subnets" {
  description = "Whether to create a dedicated ElastiCache subnet tier."
  type        = bool
  default     = false
}

variable "elasticache_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for ElastiCache subnets, one per AZ. Auto-derived from cidr_block when empty."
  type        = list(string)
  default     = []
}

variable "create_elasticache_subnet_group" {
  description = "Whether to create an aws_elasticache_subnet_group spanning the ElastiCache subnets."
  type        = bool
  default     = true
}

variable "elasticache_subnet_group_name" {
  description = "Name for the ElastiCache subnet group. Defaults to name_prefix when null."
  type        = string
  default     = null
}

## ---------------------------------------------------------------------------
## Optional — Redshift subnets (opt-in, niche)
## ---------------------------------------------------------------------------

variable "create_redshift_subnets" {
  description = "Whether to create a dedicated Redshift subnet tier. Niche — most consumers should use database_subnets for Redshift too; only enable this if you need Redshift on genuinely separate subnets/route table from RDS."
  type        = bool
  default     = false
}

variable "redshift_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for Redshift subnets, one per AZ. Auto-derived from cidr_block when empty."
  type        = list(string)
  default     = []
}

variable "create_redshift_subnet_group" {
  description = "Whether to create an aws_redshift_subnet_group spanning the Redshift subnets."
  type        = bool
  default     = true
}

variable "redshift_subnet_group_name" {
  description = "Name for the Redshift subnet group. Defaults to name_prefix when null."
  type        = string
  default     = null
}

variable "enable_public_redshift" {
  description = "Whether Redshift subnets associate with the public route table instead of a private/NAT one. Secure default is false."
  type        = bool
  default     = false
}

## ---------------------------------------------------------------------------
## Optional — Intra subnets (opt-in): fully isolated, no route to NAT or IGW
## ---------------------------------------------------------------------------

variable "create_intra_subnets" {
  description = "Whether to create \"intra\" subnets — subnets with no route to a NAT Gateway or Internet Gateway at all. Useful for workloads (e.g. Lambda-in-VPC reaching only internal resources / VPC endpoints) that should have zero internet path, not even outbound."
  type        = bool
  default     = false
}

variable "intra_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for intra subnets, one per AZ. Auto-derived from cidr_block when empty."
  type        = list(string)
  default     = []
}

variable "create_multiple_intra_route_tables" {
  description = "If true, create one intra route table per AZ instead of one shared table."
  type        = bool
  default     = false
}

## ---------------------------------------------------------------------------
## Optional — Outpost subnets (opt-in, niche)
## ---------------------------------------------------------------------------

variable "create_outpost_subnets" {
  description = "Whether to create subnets on an AWS Outpost. Niche — only relevant if you operate Outposts hardware."
  type        = bool
  default     = false
}

variable "outpost_arn" {
  description = "ARN of the Outpost to place subnets on. Required when create_outpost_subnets = true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_outpost_subnets || var.outpost_arn != null
    error_message = "outpost_arn must be set when create_outpost_subnets = true."
  }
}

variable "outpost_az" {
  description = "Availability zone the Outpost is homed to. Required when create_outpost_subnets = true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_outpost_subnets || var.outpost_az != null
    error_message = "outpost_az must be set when create_outpost_subnets = true."
  }
}

variable "outpost_subnet_cidrs" {
  description = "Explicit IPv4 CIDR blocks for Outpost subnets. Required when create_outpost_subnets = true (no AZ list to auto-derive an index from, since Outposts are single-AZ)."
  type        = list(string)
  default     = []
}

variable "customer_owned_ipv4_pool" {
  description = "Customer-owned IPv4 address pool for the Outpost subnet, if using CoIP."
  type        = string
  default     = null
}

variable "map_customer_owned_ip_on_launch" {
  description = "Whether instances launched into the Outpost subnet auto-assign a customer-owned IP."
  type        = bool
  default     = false
}

## ---------------------------------------------------------------------------
## Optional — NAT Gateway
## ---------------------------------------------------------------------------

variable "nat_gateway_strategy" {
  description = "How private (and, if enabled, database/elasticache/redshift) subnets reach the internet: \"single\" (one NAT Gateway shared across all AZs), \"one_per_az\" (one per AZ, full HA), or \"none\" (no NAT Gateway)."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "one_per_az", "none"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be one of: single, one_per_az, none."
  }
}

variable "nat_gateway_destination_cidr_block" {
  description = "Destination CIDR for the private-subnet NAT route. Override only for split-tunnel/overlapping-CIDR scenarios; almost always leave this as the default."
  type        = string
  default     = "0.0.0.0/0"
}

variable "reuse_nat_ips" {
  description = "If true, attach the Elastic IPs in external_nat_ip_ids to the NAT Gateway(s) instead of allocating new ones. Useful when downstream firewalls/allowlists are pinned to specific, already-known IPs."
  type        = bool
  default     = false
}

variable "external_nat_ip_ids" {
  description = "Pre-allocated EIP allocation IDs to reuse for NAT Gateways. Required (and must have as many entries as NAT Gateways created) when reuse_nat_ips = true."
  type        = list(string)
  default     = []
}

## ---------------------------------------------------------------------------
## Optional — Egress-only Internet Gateway (IPv6 outbound-only path)
## ---------------------------------------------------------------------------

variable "create_egress_only_igw" {
  description = "Whether to create an Egress-Only Internet Gateway for IPv6 outbound-only routing from private-tier subnets. Only takes effect when enable_ipv6 = true."
  type        = bool
  default     = true
}

## ---------------------------------------------------------------------------
## Optional — VPN Gateway & Customer Gateways
## ---------------------------------------------------------------------------

variable "enable_vpn_gateway" {
  description = "Whether to create and attach an aws_vpn_gateway to this VPC."
  type        = bool
  default     = false
}

variable "vpn_gateway_id" {
  description = "ID of an existing VPN Gateway to attach instead of creating a new one. Mutually exclusive in practice with enable_vpn_gateway = true (don't set both)."
  type        = string
  default     = null
}

variable "amazon_side_asn" {
  description = "Amazon side ASN for the VPN Gateway this module creates. Only used when enable_vpn_gateway = true."
  type        = string
  default     = "64512"
}

variable "vpn_gateway_az" {
  description = "Availability zone to create the VPN Gateway in. Leave null to let AWS choose."
  type        = string
  default     = null
}

variable "propagate_public_route_tables_vgw" {
  description = "Whether to propagate VPN Gateway routes into the public route table(s)."
  type        = bool
  default     = false
}

variable "propagate_private_route_tables_vgw" {
  description = "Whether to propagate VPN Gateway routes into the private route table(s)."
  type        = bool
  default     = false
}

variable "propagate_intra_route_tables_vgw" {
  description = "Whether to propagate VPN Gateway routes into the intra route table(s)."
  type        = bool
  default     = false
}

variable "customer_gateways" {
  description = "Map (keyed by a logical name you choose) of Customer Gateways to create for site-to-site VPN."
  type = map(object({
    bgp_asn     = number
    ip_address  = string
    device_name = optional(string)
  }))
  default = {}
}

## ---------------------------------------------------------------------------
## Optional — Default VPC / Security Group / NACL / Route Table management
## ---------------------------------------------------------------------------
## Every account gets an AWS-created default VPC, default SG, default NACL,
## and default route table whether you ask for them or not. These
## variables let you bring the ones associated with THIS module's VPC under
## Terraform management (e.g. to lock the default SG down to deny-all,
## which AWS's own default does not do). All default to false —
## least-surprise applies to the default NACL and default route table
## (manage_default_network_acl / manage_default_route_table below stay
## opt-in) — but the default SECURITY GROUP is different: AWS's own
## default there is allow-all-between-members + allow-all-egress, which is
## exactly the kind of permissive default docs/coding-standards.md §5
## prohibits (confirmed by checkov CKV2_AWS_12). So this one toggle is
## secure-by-default (true) rather than least-surprise, deliberately
## inconsistent with its NACL/route-table siblings for that reason.

variable "manage_default_security_group" {
  description = "Whether to manage this VPC's default security group and lock it to deny-all (empty ingress/egress rule lists). Defaults to true — AWS's own default security group allows all traffic between members and all egress, which this module treats as a real security gap (checkov CKV2_AWS_12), not an acceptable AWS-managed default to leave alone. Set false only if something else in your account already manages this VPC's default SG and you don't want two owners fighting over it."
  type        = bool
  default     = true
}

variable "default_security_group_ingress" {
  description = "Ingress rules for the managed default security group. Empty (the default) means deny-all inbound. Only used when manage_default_security_group = true."
  type = list(object({
    description     = optional(string)
    self            = optional(bool)
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    protocol        = optional(string, "-1")
  }))
  default = []
}

variable "default_security_group_egress" {
  description = "Egress rules for the managed default security group. Empty (the default) means deny-all outbound. Only used when manage_default_security_group = true."
  type = list(object({
    description     = optional(string)
    self            = optional(bool)
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    protocol        = optional(string, "-1")
  }))
  default = []
}

variable "manage_default_network_acl" {
  description = "Whether to manage this VPC's default network ACL (the one AWS auto-creates, distinct from the per-tier custom NACLs this module can also create). Only used to explicitly lock down or document the default NACL's rules; leave false to not touch it."
  type        = bool
  default     = false
}

variable "default_network_acl_ingress" {
  description = "Ingress rules for the managed default NACL. Only used when manage_default_network_acl = true."
  type = list(object({
    rule_no         = number
    action          = string
    protocol        = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "default_network_acl_egress" {
  description = "Egress rules for the managed default NACL. Only used when manage_default_network_acl = true."
  type = list(object({
    rule_no         = number
    action          = string
    protocol        = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "manage_default_route_table" {
  description = "Whether to manage this VPC's default route table (distinct from the public/private/etc. route tables this module creates explicitly). Only used when you need to document/control what's in the AWS-auto-created default; leave false otherwise."
  type        = bool
  default     = false
}

variable "default_route_table_routes" {
  description = "Routes for the managed default route table. Only used when manage_default_route_table = true."
  type = list(object({
    cidr_block                = optional(string)
    ipv6_cidr_block           = optional(string)
    gateway_id                = optional(string)
    nat_gateway_id            = optional(string)
    vpc_peering_connection_id = optional(string)
    transit_gateway_id        = optional(string)
    vpc_endpoint_id           = optional(string)
    egress_only_gateway_id    = optional(string)
  }))
  default = []
}

## ---------------------------------------------------------------------------
## Optional — VPC Flow Logs
## ---------------------------------------------------------------------------
## Two modes, not mutually exclusive with each other's off-switch:
##   1. Self-contained (default): the module creates its own CloudWatch Log
##      Group + a least-privilege IAM role/policy scoped to that one log
##      group's ARN (no Resource = "*"), and points the flow log at them.
##   2. Bring-your-own: set create_flow_log_cloudwatch_log_group = false
##      and/or create_flow_log_cloudwatch_iam_role = false and supply
##      flow_log_destination_arn / flow_log_iam_role_arn yourself — e.g. to
##      centralize flow logs from many VPCs into one Log Group the
##      cloudwatch/iam modules own.
## S3 destinations never need an IAM role (delivery uses a resource policy
## on the bucket instead), so flow_log_destination_type = "s3" ignores every
## *_iam_role_* variable below.

variable "enable_flow_logs" {
  description = "Whether to create a VPC Flow Log."
  type        = bool
  default     = false
}

variable "flow_log_destination_type" {
  description = "Where flow logs are delivered: \"cloud-watch-logs\" or \"s3\"."
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_log_destination_type)
    error_message = "flow_log_destination_type must be one of: cloud-watch-logs, s3."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of an existing CloudWatch Log Group or S3 bucket to deliver flow logs to. Required when the corresponding create_flow_log_cloudwatch_log_group is false (bring-your-own mode) or when flow_log_destination_type = \"s3\" (this module never creates an S3 bucket). Ignored (self-contained mode) when destination_type = \"cloud-watch-logs\" and create_flow_log_cloudwatch_log_group = true."
  type        = string
  default     = null

  validation {
    condition = !var.enable_flow_logs || var.flow_log_destination_type == "s3" && var.flow_log_destination_arn != null || var.flow_log_destination_type == "cloud-watch-logs" && (var.create_flow_log_cloudwatch_log_group || var.flow_log_destination_arn != null)
    error_message = "flow_log_destination_arn must be set when flow_log_destination_type = \"s3\", or when destination_type = \"cloud-watch-logs\" and create_flow_log_cloudwatch_log_group = false."
  }
}

variable "flow_log_traffic_type" {
  description = "Type of traffic to capture in the flow log."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be one of: ACCEPT, REJECT, ALL."
  }
}

variable "flow_log_log_format" {
  description = "Custom flow log record format. Leave null for the AWS default field set."
  type        = string
  default     = null
}

variable "flow_log_max_aggregation_interval" {
  description = "Maximum interval (seconds) at which flow log records are captured."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600 (AWS-supported values)."
  }
}

variable "flow_log_deliver_cross_account_role" {
  description = "IAM role ARN used when the flow log destination lives in a different account than this VPC. Leave null for same-account delivery."
  type        = string
  default     = null
}

## --- S3 destination options (only used when flow_log_destination_type = "s3") ---

variable "flow_log_file_format" {
  description = "File format for flow logs delivered to S3."
  type        = string
  default     = "plain-text"

  validation {
    condition     = contains(["plain-text", "parquet"], var.flow_log_file_format)
    error_message = "flow_log_file_format must be one of: plain-text, parquet."
  }
}

variable "flow_log_hive_compatible_partitions" {
  description = "Whether S3-delivered flow logs use Hive-compatible S3 prefixes."
  type        = bool
  default     = false
}

variable "flow_log_per_hour_partition" {
  description = "Whether S3-delivered flow logs are additionally partitioned by hour."
  type        = bool
  default     = false
}

## --- Self-contained CloudWatch Log Group (destination_type = "cloud-watch-logs") ---

variable "create_flow_log_cloudwatch_log_group" {
  description = "Whether this module creates its own CloudWatch Log Group for flow logs. Only relevant when flow_log_destination_type = \"cloud-watch-logs\". Set false and supply flow_log_destination_arn to bring your own (e.g. a centralized Log Group owned by the cloudwatch module)."
  type        = bool
  default     = true
}

variable "flow_log_cloudwatch_log_group_name_prefix" {
  description = "Prefix for the auto-created Log Group's name."
  type        = string
  default     = "/aws/vpc-flow-log/"
}

variable "flow_log_cloudwatch_log_group_name_suffix" {
  description = "Suffix for the auto-created Log Group's name. Defaults to the VPC ID when left empty."
  type        = string
  default     = ""
}

variable "flow_log_cloudwatch_log_group_retention_in_days" {
  description = "Retention period for the auto-created Log Group."
  type        = number
  default     = 365
}

variable "flow_log_cloudwatch_log_group_kms_key_id" {
  description = "KMS key ARN to encrypt the auto-created Log Group with. Leave null to use CloudWatch Logs' default encryption."
  type        = string
  default     = null
}

variable "flow_log_cloudwatch_log_group_skip_destroy" {
  description = "Whether to keep the Log Group on destroy (skips deleting existing log data when the VPC is torn down)."
  type        = bool
  default     = false
}

variable "flow_log_cloudwatch_log_group_class" {
  description = "Log Group class: \"STANDARD\" or \"INFREQUENT_ACCESS\"."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "INFREQUENT_ACCESS"], var.flow_log_cloudwatch_log_group_class)
    error_message = "flow_log_cloudwatch_log_group_class must be one of: STANDARD, INFREQUENT_ACCESS."
  }
}

## --- Self-contained IAM role for CloudWatch delivery ------------------------

variable "create_flow_log_cloudwatch_iam_role" {
  description = "Whether this module creates a least-privilege IAM role + policy (scoped to only the flow log's own Log Group ARN, never Resource = \"*\") for the flow log service to assume. Only relevant when flow_log_destination_type = \"cloud-watch-logs\". Set false and supply flow_log_iam_role_arn to bring your own."
  type        = bool
  default     = true
}

variable "flow_log_iam_role_arn" {
  description = "Existing IAM role ARN for the flow log service to assume. Required when create_flow_log_cloudwatch_iam_role = false and flow_log_destination_type = \"cloud-watch-logs\"."
  type        = string
  default     = null
}

variable "vpc_flow_log_iam_role_name" {
  description = "Name (or name prefix, per vpc_flow_log_iam_role_use_name_prefix) for the auto-created IAM role."
  type        = string
  default     = null
}

variable "vpc_flow_log_iam_role_use_name_prefix" {
  description = "Whether vpc_flow_log_iam_role_name is used as a name_prefix instead of an exact name."
  type        = bool
  default     = true
}

variable "vpc_flow_log_iam_role_path" {
  description = "IAM path for the auto-created flow log role."
  type        = string
  default     = "/"
}

variable "vpc_flow_log_permissions_boundary" {
  description = "Permissions boundary ARN to attach to the auto-created flow log IAM role."
  type        = string
  default     = null
}

variable "vpc_flow_log_iam_policy_name" {
  description = "Name (or name prefix) for the auto-created IAM policy."
  type        = string
  default     = null
}

variable "vpc_flow_log_iam_policy_use_name_prefix" {
  description = "Whether vpc_flow_log_iam_policy_name is used as a name_prefix instead of an exact name."
  type        = bool
  default     = true
}

variable "flow_log_cloudwatch_iam_role_conditions" {
  description = "Extra IAM assume-role policy conditions for the auto-created role (e.g. sts:ExternalId for cross-account delivery)."
  type = list(object({
    test     = string
    variable = string
    values   = list(string)
  }))
  default = []
}

variable "vpc_flow_log_tags" {
  description = "Additional tags applied only to flow-log-related resources (the flow log itself, Log Group, IAM role/policy), on top of local.common_tags."
  type        = map(string)
  default     = {}
}

## ---------------------------------------------------------------------------
## Optional — Network ACLs (per tier, opt-in). Secure-by-default: leaving
## these unmanaged means subnets keep the VPC's default NACL (allow-all),
## matching AWS's own default. Setting manage_*_network_acl = true with an
## empty rule list produces a deny-all NACL for that tier — no synthesized
## allow-all fallback.
## ---------------------------------------------------------------------------

variable "manage_public_network_acl" {
  description = "Create a custom NACL for public subnets. Deny-all if the rule lists are left empty."
  type        = bool
  default     = false
}

variable "public_network_acl_ingress_rules" {
  description = "Ingress rules for the public subnets' NACL. Only used when manage_public_network_acl = true."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "public_network_acl_egress_rules" {
  description = "Egress rules for the public subnets' NACL. Only used when manage_public_network_acl = true."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "manage_private_network_acl" {
  description = "Create a custom NACL for private subnets. Deny-all if the rule lists are left empty."
  type        = bool
  default     = false
}

variable "private_network_acl_ingress_rules" {
  description = "Ingress rules for the private subnets' NACL. Only used when manage_private_network_acl = true."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "private_network_acl_egress_rules" {
  description = "Egress rules for the private subnets' NACL. Only used when manage_private_network_acl = true."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "manage_database_network_acl" {
  description = "Create a custom NACL for database subnets. Deny-all if the rule lists are left empty. Only applies when create_database_subnets = true."
  type        = bool
  default     = false
}

variable "database_network_acl_ingress_rules" {
  description = "Ingress rules for the database subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "database_network_acl_egress_rules" {
  description = "Egress rules for the database subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "manage_elasticache_network_acl" {
  description = "Create a custom NACL for ElastiCache subnets. Only applies when create_elasticache_subnets = true."
  type        = bool
  default     = false
}

variable "elasticache_network_acl_ingress_rules" {
  description = "Ingress rules for the ElastiCache subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "elasticache_network_acl_egress_rules" {
  description = "Egress rules for the ElastiCache subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "manage_intra_network_acl" {
  description = "Create a custom NACL for intra subnets. Only applies when create_intra_subnets = true."
  type        = bool
  default     = false
}

variable "intra_network_acl_ingress_rules" {
  description = "Ingress rules for the intra subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

variable "intra_network_acl_egress_rules" {
  description = "Egress rules for the intra subnets' NACL."
  type = list(object({
    rule_number     = number
    protocol        = string
    rule_action     = string
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = []
}

## ---------------------------------------------------------------------------
## Tags
## ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to every resource this module creates, merged with module-computed tags (Environment, ManagedBy, Module). Ownership metadata (Owner, CostCenter, etc.) belongs here — see docs/coding-standards.md §4 — this module deliberately has no dedicated owner variable."
  type        = map(string)
  default     = {}
}
