# ============================================
# TERRAFORM LOCAL VALUES - Complete Examples
# ============================================

terraform {
  required_version = ">= 1.5.0"
}

# ============================================
# VARIABLES
# ============================================

variable "project_name" {
  default = "myproject"
}

variable "environment" {
  default = "dev"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "instance_count" {
  default = 2
}

variable "tags" {
  type = map(string)
  default = {
    Team = "DevOps"
  }
}

# ============================================
# LOCAL VALUES
# ============================================

locals {
  # ==========================================
  # BASIC COMPUTED VALUES
  # ==========================================
  
  # String concatenation
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Boolean expressions
  is_production = var.environment == "prod"
  is_dev_or_stg = contains(["dev", "stg"], var.environment)
  
  # Conditional values
  instance_type = local.is_production ? "t3.large" : "t3.micro"
  
  # ==========================================
  # TAG MANAGEMENT
  # ==========================================
  
  # Common tags applied to all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }
  
  # Merge with user-provided tags
  all_tags = merge(local.common_tags, var.tags)
  
  # Environment-specific tags
  env_tags = {
    dev = {
      CostCenter = "Development"
      AutoShutdown = "true"
    }
    stg = {
      CostCenter = "QA"
      AutoShutdown = "false"
    }
    prod = {
      CostCenter    = "Production"
      AutoShutdown  = "false"
      Compliance    = "SOC2"
    }
  }
  
  final_tags = merge(
    local.all_tags,
    lookup(local.env_tags, var.environment, {})
  )
  
  # ==========================================
  # COMPUTED LISTS AND MAPS
  # ==========================================
  
  # Generate instance names
  instance_names = [
    for i in range(var.instance_count) : "${local.name_prefix}-instance-${i + 1}"
  ]
  
  # Create map from list
  instance_config = {
    for i in range(var.instance_count) : "instance-${i + 1}" => {
      name = "${local.name_prefix}-instance-${i + 1}"
      az   = element(["us-east-1a", "us-east-1b"], i)
      type = local.instance_type
    }
  }
  
  # ==========================================
  # NETWORK CALCULATIONS
  # ==========================================
  
  vpc_cidr = "10.0.0.0/16"
  
  # Calculate subnet CIDRs
  public_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 8, 0),   # 10.0.0.0/24
    cidrsubnet(local.vpc_cidr, 8, 1),   # 10.0.1.0/24
    cidrsubnet(local.vpc_cidr, 8, 2),   # 10.0.2.0/24
  ]
  
  private_subnet_cidrs = [
    cidrsubnet(local.vpc_cidr, 8, 10),  # 10.0.10.0/24
    cidrsubnet(local.vpc_cidr, 8, 11),  # 10.0.11.0/24
    cidrsubnet(local.vpc_cidr, 8, 12),  # 10.0.12.0/24
  ]
  
  # ==========================================
  # COMPLEX DATA TRANSFORMATIONS
  # ==========================================
  
  # Input: list of users with roles
  users_input = [
    { name = "alice", role = "admin", email = "alice@example.com" },
    { name = "bob", role = "developer", email = "bob@example.com" },
    { name = "carol", role = "admin", email = "carol@example.com" },
    { name = "david", role = "viewer", email = "david@example.com" },
  ]
  
  # Group users by role
  users_by_role = {
    for user in local.users_input : user.role => user.name...
  }
  # Result: { admin = ["alice", "carol"], developer = ["bob"], viewer = ["david"] }
  
  # Filter admins only
  admin_users = [
    for user in local.users_input : user
    if user.role == "admin"
  ]
  
  # Create map keyed by name
  users_map = {
    for user in local.users_input : user.name => user
  }
  
  # ==========================================
  # CONFIGURATION LOOKUPS
  # ==========================================
  
  # Instance type mapping
  instance_types = {
    dev  = "t3.micro"
    stg  = "t3.small"
    prod = "t3.medium"
  }
  
  # RDS configuration by environment
  rds_config = {
    dev = {
      instance_class = "db.t3.micro"
      storage        = 20
      multi_az       = false
      backup_days    = 1
    }
    stg = {
      instance_class = "db.t3.small"
      storage        = 50
      multi_az       = false
      backup_days    = 7
    }
    prod = {
      instance_class = "db.r6g.large"
      storage        = 200
      multi_az       = true
      backup_days    = 30
    }
  }
  
  current_rds_config = local.rds_config[var.environment]
  
  # ==========================================
  # FILE PATHS
  # ==========================================
  
  config_path    = "${path.module}/config"
  templates_path = "${path.module}/templates"
  scripts_path   = "${path.root}/scripts"
  
  # ==========================================
  # JSON/YAML ENCODING
  # ==========================================
  
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${local.name_prefix}-bucket/*"]
      }
    ]
  })
  
  config_yaml = yamlencode({
    app = {
      name        = var.project_name
      environment = var.environment
      features = {
        logging    = true
        monitoring = local.is_production
      }
    }
  })
  
  # ==========================================
  # DATE/TIME
  # ==========================================
  
  current_timestamp = timestamp()
  current_date      = formatdate("YYYY-MM-DD", timestamp())
  
  # Note: Using timestamp() makes the plan non-deterministic
  # Use only when needed, like for tagging
}

# ============================================
# OUTPUTS
# ============================================

output "name_prefix" {
  value = local.name_prefix
}

output "is_production" {
  value = local.is_production
}

output "instance_type" {
  value = local.instance_type
}

output "all_tags" {
  value = local.final_tags
}

output "instance_names" {
  value = local.instance_names
}

output "instance_config" {
  value = local.instance_config
}

output "subnet_cidrs" {
  value = {
    public  = local.public_subnet_cidrs
    private = local.private_subnet_cidrs
  }
}

output "users_by_role" {
  value = local.users_by_role
}

output "admin_users" {
  value = local.admin_users
}

output "current_rds_config" {
  value = local.current_rds_config
}
