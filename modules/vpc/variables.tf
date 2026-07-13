## ---------------------------------------------------------------------------
## Required (minimal surface for the common case)
## ---------------------------------------------------------------------------

variable "name" {
  description = "Name identifier for this VPC, used as the resource name prefix (e.g. \"payments-prod\"). Combined with var.environment in tags but kept independent so a consumer can name it however their org convention requires."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 40
    error_message = "name must be between 1 and 40 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Used in local.common_tags and, indirectly, in the default name_prefix fallback."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "shared"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, shared."
  }
}

variable "cidr_block" {
  description = "Primary IPv4 CIDR block for the VPC (e.g. \"10.20.0.0/16\"). Must be a /28 or larger per AWS VPC limits; subnet CIDRs are auto-derived from this block unless public_subnet_cidrs/private_subnet_cidrs are explicitly supplied."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR notation, e.g. \"10.20.0.0/16\"."
  }
}

## ---------------------------------------------------------------------------
## Optional — availability zones & subnets
## ---------------------------------------------------------------------------

variable "availability_zones" {
  description = "Explicit list of AZs to use (e.g. [\"us-east-1a\", \"us-east-1b\"]). If empty (the default), the module selects the first availability_zone_count AZs (alphabetically) returned by the aws_availability_zones data source for the caller's configured region."
  type        = list(string)
  default     = []
}

variable "availability_zone_count" {
  description = "Number of AZs to auto-select when var.availability_zones is not supplied. Ignored if var.availability_zones is non-empty."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 6
    error_message = "availability_zone_count must be between 1 and 6."
  }
}

variable "create_public_subnets" {
  description = "Whether to create public subnets (and the Internet Gateway + public route table they need). Set to false for a fully private VPC (e.g. one reached only via Transit Gateway/VPN)."
  type        = bool
  default     = true
}

variable "create_private_subnets" {
  description = "Whether to create private subnets."
  type        = bool
  default     = true
}

variable "public_subnet_cidrs" {
  description = "Explicit CIDR blocks for public subnets, one per AZ in order. If empty (the default) and create_public_subnets = true, CIDRs are auto-derived from var.cidr_block via cidrsubnet(), offset before the private subnets so both tiers can grow independently."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Explicit CIDR blocks for private subnets, one per AZ in order. If empty (the default) and create_private_subnets = true, CIDRs are auto-derived from var.cidr_block via cidrsubnet()."
  type        = list(string)
  default     = []
}

variable "map_public_ip_on_launch" {
  description = "Whether instances launched into public subnets automatically receive a public IP. Defaults to false (secure default); enable only if you understand the exposure implications for what gets launched into these subnets."
  type        = bool
  default     = false
}

## ---------------------------------------------------------------------------
## Optional — VPC-level configuration
## ---------------------------------------------------------------------------

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

variable "instance_tenancy" {
  description = "Tenancy of instances launched into the VPC by default."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "instance_tenancy must be either \"default\" or \"dedicated\"."
  }
}

## ---------------------------------------------------------------------------
## Optional — NAT Gateway strategy
## ---------------------------------------------------------------------------

variable "nat_gateway_strategy" {
  description = "How private subnets reach the internet: \"single\" (one NAT Gateway shared across all AZs — lowest cost, single point of failure), \"one_per_az\" (one NAT Gateway per AZ — full HA, highest cost), or \"none\" (no NAT Gateway; private subnets have no outbound internet path unless the caller wires up something else, e.g. a Transit Gateway route)."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "one_per_az", "none"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be one of: single, one_per_az, none."
  }
}

## ---------------------------------------------------------------------------
## Optional — VPC Flow Logs
## ---------------------------------------------------------------------------
## This module intentionally does NOT create the CloudWatch Log Group, S3
## bucket, or IAM role a flow log needs — that's the cloudwatch/s3/iam
## modules' job (composability, per docs/coding-standards.md design
## principle #3). Pass in an existing destination ARN.

variable "enable_flow_logs" {
  description = "Whether to create a VPC Flow Log. Requires flow_log_destination_arn to be set."
  type        = bool
  default     = false
}

variable "flow_log_destination_arn" {
  description = "ARN of the CloudWatch Log Group or S3 bucket flow logs are delivered to. Required when enable_flow_logs = true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_flow_logs || var.flow_log_destination_arn != null
    error_message = "flow_log_destination_arn must be set when enable_flow_logs = true."
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

variable "flow_log_iam_role_arn" {
  description = "IAM role ARN the flow log service uses to publish to the destination. Required only when flow_log_destination_arn points at a CloudWatch Log Group (not required for S3 destinations)."
  type        = string
  default     = null
}

## ---------------------------------------------------------------------------
## Optional — Network ACLs
## ---------------------------------------------------------------------------
## Secure-by-default: leaving these unmanaged (the default) means subnets
## keep the VPC's default NACL (allow-all), matching AWS's own default
## behavior and every consumer's expectation of "subnets just work" unless
## they opt in to lockdown. Setting manage_*_network_acl = true with an
## empty rule list produces a deny-all NACL (see aws_network_acl.public/private in main.tf).

variable "manage_public_network_acl" {
  description = "Whether to create and associate a custom NACL for public subnets. If true and public_network_acl_ingress_rules/egress_rules are left empty, the NACL denies all traffic — you must supply explicit rules."
  type        = bool
  default     = false
}

variable "public_network_acl_ingress_rules" {
  description = "Ingress rules for the public subnets' NACL. Only used when manage_public_network_acl = true."
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

variable "public_network_acl_egress_rules" {
  description = "Egress rules for the public subnets' NACL. Only used when manage_public_network_acl = true."
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

variable "manage_private_network_acl" {
  description = "Whether to create and associate a custom NACL for private subnets. Same deny-if-empty behavior as manage_public_network_acl."
  type        = bool
  default     = false
}

variable "private_network_acl_ingress_rules" {
  description = "Ingress rules for the private subnets' NACL. Only used when manage_private_network_acl = true."
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

variable "private_network_acl_egress_rules" {
  description = "Egress rules for the private subnets' NACL. Only used when manage_private_network_acl = true."
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
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
