# ============================================
# TERRAFORM VARIABLE TYPES - Complete Guide
# ============================================
# This file demonstrates ALL variable types in Terraform

# ============================================
# 1. STRING VARIABLE
# ============================================
# Basic string variable with default value
variable "environment" {
  description = "Deployment environment (dev, stg, prod)"
  type        = string
  default     = "dev"

  # Validation rule for string
  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod."
  }
}

# String without default (required)
variable "project_name" {
  description = "Name of the project"
  type        = string
  # No default = required variable
}

# String with sensitive flag (for secrets)
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true  # Won't be displayed in logs/output
  default     = ""
}

# ============================================
# 2. NUMBER VARIABLE
# ============================================
variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 50
}

# ============================================
# 3. BOOLEAN VARIABLE
# ============================================
variable "enable_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

variable "create_dns_record" {
  description = "Whether to create DNS record"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

# ============================================
# 4. LIST VARIABLE (Ordered, allows duplicates)
# ============================================
# Simple list of strings
variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# List of numbers
variable "allowed_ports" {
  description = "List of allowed ports"
  type        = list(number)
  default     = [22, 80, 443, 8080]
}

# List of any type
variable "mixed_list" {
  description = "List with any type (not recommended)"
  type        = list(any)
  default     = ["string", 123, true]
}

# ============================================
# 5. SET VARIABLE (Unordered, unique values)
# ============================================
variable "security_group_ids" {
  description = "Set of security group IDs"
  type        = set(string)
  default     = []
}

variable "unique_tags" {
  description = "Unique set of tags"
  type        = set(string)
  default     = ["web", "api", "backend"]
}

# ============================================
# 6. MAP VARIABLE (Key-value pairs)
# ============================================
# Simple string map
variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    Project     = "MyProject"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Map of numbers (e.g., instance counts per environment)
variable "instance_counts" {
  description = "Instance count per environment"
  type        = map(number)
  default = {
    dev  = 1
    stg  = 2
    prod = 3
  }
}

# Map of any type
variable "ami_ids" {
  description = "AMI IDs per region"
  type        = map(string)
  default = {
    us-east-1 = "ami-0123456789abcdef0"
    us-west-2 = "ami-0987654321fedcba0"
    eu-west-1 = "ami-0abcdef1234567890"
  }
}

# ============================================
# 7. OBJECT VARIABLE (Structured data)
# ============================================
# Simple object
variable "instance_config" {
  description = "EC2 instance configuration"
  type = object({
    instance_type = string
    ami_id        = string
    volume_size   = number
    encrypted     = bool
  })
  default = {
    instance_type = "t3.micro"
    ami_id        = "ami-0123456789abcdef0"
    volume_size   = 30
    encrypted     = true
  }
}

# Complex nested object
variable "vpc_config" {
  description = "VPC configuration"
  type = object({
    cidr_block           = string
    enable_dns_hostnames = bool
    enable_dns_support   = bool
    subnets = list(object({
      cidr_block        = string
      availability_zone = string
      public            = bool
    }))
  })
  default = {
    cidr_block           = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support   = true
    subnets = [
      {
        cidr_block        = "10.0.1.0/24"
        availability_zone = "us-east-1a"
        public            = true
      },
      {
        cidr_block        = "10.0.2.0/24"
        availability_zone = "us-east-1b"
        public            = false
      }
    ]
  }
}

# Object with optional attributes (Terraform 1.3+)
variable "database_config" {
  description = "Database configuration with optional settings"
  type = object({
    engine         = string
    engine_version = string
    instance_class = string
    # Optional with defaults
    allocated_storage = optional(number, 20)
    multi_az          = optional(bool, false)
    backup_retention  = optional(number, 7)
    # Optional without default (will be null if not provided)
    snapshot_id = optional(string)
  })
  default = {
    engine         = "postgres"
    engine_version = "15.4"
    instance_class = "db.t3.micro"
  }
}

# ============================================
# 8. TUPLE VARIABLE (Fixed-length, mixed types)
# ============================================
variable "server_tuple" {
  description = "Server config as tuple [name, port, enabled]"
  type        = tuple([string, number, bool])
  default     = ["web-server", 8080, true]
}

variable "scaling_config" {
  description = "Scaling config [min, max, desired]"
  type        = tuple([number, number, number])
  default     = [1, 5, 2]

  validation {
    condition     = var.scaling_config[0] <= var.scaling_config[2] && var.scaling_config[2] <= var.scaling_config[1]
    error_message = "Scaling config must satisfy: min <= desired <= max."
  }
}

# ============================================
# 9. ANY TYPE (Flexible, inferred)
# ============================================
variable "flexible_value" {
  description = "Accepts any type"
  type        = any
  default     = "default-string"
}

# ============================================
# 10. NULLABLE VARIABLES
# ============================================
variable "optional_description" {
  description = "Optional description that can be null"
  type        = string
  default     = null
  nullable    = true  # Explicitly allow null (default is true for variables with default = null)
}

# ============================================
# 11. COMPLEX VALIDATION EXAMPLES
# ============================================
variable "cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "email" {
  description = "Notification email"
  type        = string
  default     = "admin@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email))
    error_message = "Must be a valid email address."
  }
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
  default     = "my-unique-bucket-name"

  validation {
    condition     = length(var.s3_bucket_name) >= 3 && length(var.s3_bucket_name) <= 63
    error_message = "S3 bucket name must be between 3 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must start and end with lowercase letter or number."
  }
}
