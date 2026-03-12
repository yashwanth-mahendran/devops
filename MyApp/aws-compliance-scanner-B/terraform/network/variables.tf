################################################################################
# General Variables
################################################################################

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "compliance-scanner"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

################################################################################
# VPC Variables
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "enable_ha_nat" {
  description = "Enable multi-AZ NAT Gateway for high availability (one per AZ)"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period for VPC Flow Logs (days)"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Retention must be a valid CloudWatch Logs retention value."
  }
}

################################################################################
# Security Variables
################################################################################

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access ALB (use ['0.0.0.0/0'] for public)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ip_addresses" {
  description = "IP addresses for WAF allowlist (CIDR format, e.g., '203.0.113.0/24')"
  type        = list(string)
  default     = []
}

variable "blocked_ip_addresses" {
  description = "IP addresses for WAF blocklist (CIDR format)"
  type        = list(string)
  default     = []
}

variable "blocked_countries" {
  description = "Country codes to block via WAF geo-restriction (e.g., ['RU', 'CN', 'KP'])"
  type        = list(string)
  default     = []
}

variable "waf_rate_limit" {
  description = "WAF rate limit: max requests per 5 minutes per IP"
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000."
  }
}

variable "waf_log_retention_days" {
  description = "Retention period for WAF logs (days)"
  type        = number
  default     = 30
}

################################################################################
# Certificate/TLS Variables
################################################################################

variable "domain_name" {
  description = "Domain name for the application (e.g., compliance-scanner.company.com)"
  type        = string
  default     = ""
}

variable "certificate_sans" {
  description = "Subject Alternative Names for the certificate"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS validation and record creation"
  type        = string
  default     = ""
}

variable "create_certificate" {
  description = "Whether to create an ACM certificate"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN (if not creating new)"
  type        = string
  default     = ""
}

################################################################################
# ALB Variables
################################################################################

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = false
}

variable "alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
  default     = ""
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
