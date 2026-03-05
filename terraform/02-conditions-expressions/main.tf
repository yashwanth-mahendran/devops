# ============================================
# TERRAFORM CONDITIONS & EXPRESSIONS
# ============================================
# Comprehensive examples of conditionals in Terraform

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================
# VARIABLES FOR CONDITION EXAMPLES
# ============================================
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "create_resource" {
  type    = bool
  default = true
}

variable "instance_type_override" {
  type    = string
  default = ""
}

variable "enable_enhanced_monitoring" {
  type    = bool
  default = false
}

variable "custom_ami" {
  type    = string
  default = null
}

# ============================================
# 1. TERNARY CONDITIONAL OPERATOR
# ============================================
# Syntax: condition ? true_value : false_value

locals {
  # Basic ternary
  instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"

  # Nested ternary (use sparingly)
  instance_class = (
    var.environment == "prod" ? "t3.large" :
    var.environment == "stg" ? "t3.medium" :
    "t3.micro"
  )

  # Ternary with override
  final_instance_type = var.instance_type_override != "" ? var.instance_type_override : local.instance_type

  # Boolean ternary
  enable_monitoring = var.environment == "prod" ? true : var.enable_enhanced_monitoring

  # Numeric ternary
  instance_count = var.environment == "prod" ? 3 : 1
  volume_size    = var.environment == "prod" ? 100 : 30

  # String ternary
  name_prefix = var.environment == "prod" ? "production" : "development"
}

# ============================================
# 2. COUNT CONDITIONAL (Create or not)
# ============================================
# count = 0 means resource won't be created
# count = 1 means resource will be created

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  count = var.environment == "prod" ? 1 : 0

  alarm_name          = "high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization exceeded 80%"
}

# Using boolean variable
resource "aws_sns_topic" "alerts" {
  count = var.create_resource ? 1 : 0
  name  = "alerts-topic"
}

# ============================================
# 3. FOR_EACH CONDITIONAL
# ============================================
variable "optional_buckets" {
  type = map(object({
    enabled = bool
    acl     = string
  }))
  default = {
    logs = {
      enabled = true
      acl     = "private"
    }
    backups = {
      enabled = false
      acl     = "private"
    }
  }
}

resource "aws_s3_bucket" "conditional_buckets" {
  for_each = {
    for name, config in var.optional_buckets : name => config
    if config.enabled
  }

  bucket = "my-project-${each.key}-bucket"
  tags = {
    Name = each.key
  }
}

# ============================================
# 4. COALESCE AND NULL HANDLING
# ============================================
variable "ami_id" {
  type    = string
  default = null
}

variable "backup_ami_id" {
  type    = string
  default = "ami-0123456789abcdef0"
}

locals {
  # coalesce - returns first non-null/non-empty value
  selected_ami = coalesce(var.ami_id, var.backup_ami_id, "ami-fallback")

  # coalescelist - returns first non-empty list
  security_groups = coalescelist(var.custom_security_groups, ["sg-default"])

  # try - returns first expression that doesn't error
  parsed_port = try(tonumber(var.port_string), 8080)

  # Null conditional with try
  optional_value = try(var.custom_ami, null)
}

variable "custom_security_groups" {
  type    = list(string)
  default = []
}

variable "port_string" {
  type    = string
  default = "8080"
}

# ============================================
# 5. CAN() FOR VALIDATION
# ============================================
variable "maybe_json" {
  type    = string
  default = "{\"key\": \"value\"}"
}

locals {
  # Check if string is valid JSON
  is_valid_json = can(jsondecode(var.maybe_json))

  # Parse JSON only if valid
  parsed_json = local.is_valid_json ? jsondecode(var.maybe_json) : {}

  # Validate CIDR
  is_valid_cidr = can(cidrhost("10.0.0.0/16", 0))
}

# ============================================
# 6. CONTAINS() FOR LIST CHECKING
# ============================================
variable "allowed_regions" {
  type    = list(string)
  default = ["us-east-1", "us-west-2", "eu-west-1"]
}

locals {
  # Check if current region is allowed
  is_region_allowed = contains(var.allowed_regions, var.aws_region)

  # Conditional based on contains
  region_config = contains(["us-east-1", "us-west-2"], var.aws_region) ? "US" : "OTHER"
}

# ============================================
# 7. LOOKUP() WITH DEFAULT
# ============================================
variable "instance_types" {
  type = map(string)
  default = {
    dev  = "t3.micro"
    stg  = "t3.small"
    prod = "t3.medium"
  }
}

locals {
  # Lookup with fallback
  selected_instance = lookup(var.instance_types, var.environment, "t3.nano")

  # Nested lookup
  ami_mapping = {
    us-east-1 = {
      dev  = "ami-dev-east"
      prod = "ami-prod-east"
    }
    us-west-2 = {
      dev  = "ami-dev-west"
      prod = "ami-prod-west"
    }
  }

  regional_ami = lookup(lookup(local.ami_mapping, var.aws_region, {}), var.environment, "ami-default")
}

# ============================================
# 8. COMPLEX CONDITIONAL LOGIC
# ============================================
locals {
  # AND condition
  enable_detailed_monitoring = var.environment == "prod" && var.enable_enhanced_monitoring

  # OR condition  
  needs_backup = var.environment == "prod" || var.environment == "stg"

  # NOT condition
  is_ephemeral = !(var.environment == "prod")

  # Combined conditions
  apply_strict_security = (
    var.environment == "prod" &&
    contains(["us-east-1", "eu-west-1"], var.aws_region) &&
    var.create_resource
  )

  # Complex selection
  security_level = (
    var.environment == "prod" && local.is_region_allowed ? "high" :
    var.environment == "stg" ? "medium" :
    "low"
  )
}

# ============================================
# 9. DYNAMIC BLOCK WITH CONDITION
# ============================================
variable "enable_https" {
  type    = bool
  default = true
}

variable "enable_ssh" {
  type    = bool
  default = false
}

locals {
  ingress_rules = concat(
    [
      {
        port        = 80
        protocol    = "tcp"
        description = "HTTP"
      }
    ],
    var.enable_https ? [
      {
        port        = 443
        protocol    = "tcp"
        description = "HTTPS"
      }
    ] : [],
    var.enable_ssh ? [
      {
        port        = 22
        protocol    = "tcp"
        description = "SSH"
      }
    ] : []
  )
}

resource "aws_security_group" "conditional_sg" {
  name        = "conditional-sg"
  description = "Security group with conditional rules"

  dynamic "ingress" {
    for_each = local.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ["0.0.0.0/0"]
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ============================================
# 10. ONE() FUNCTION FOR SINGLE ELEMENT
# ============================================
# Useful when count creates 0 or 1 resources

# Reference: one(aws_sns_topic.alerts[*].arn)
# Returns the single element or null if empty

# ============================================
# OUTPUTS WITH CONDITIONS
# ============================================
output "instance_type" {
  value = local.instance_type
}

output "security_level" {
  value = local.security_level
}

output "monitoring_enabled" {
  value = local.enable_monitoring ? "Yes" : "No"
}

output "alarm_arn" {
  value = var.environment == "prod" ? aws_cloudwatch_metric_alarm.cpu_alarm[0].arn : "N/A"
}
