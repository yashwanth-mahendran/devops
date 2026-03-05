# ============================================
# TERRAFORM WORKSPACES - Complete Guide
# ============================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend with workspace support
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "workspaces/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Each workspace gets its own state file
    # State path: workspaces/env:/WORKSPACE_NAME/terraform.tfstate
    workspace_key_prefix = "env"
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================
# WORKSPACE-AWARE CONFIGURATION
# ============================================

variable "aws_region" {
  default = "us-east-1"
}

# Use workspace name for environment
locals {
  # terraform.workspace returns current workspace name
  environment = terraform.workspace

  # Map workspace to configuration
  workspace_config = {
    default = {
      instance_type  = "t3.micro"
      instance_count = 1
      enable_rds     = false
    }
    dev = {
      instance_type  = "t3.micro"
      instance_count = 1
      enable_rds     = false
    }
    stg = {
      instance_type  = "t3.small"
      instance_count = 2
      enable_rds     = true
    }
    prod = {
      instance_type  = "t3.medium"
      instance_count = 3
      enable_rds     = true
    }
  }

  # Get config for current workspace (with fallback)
  config = lookup(local.workspace_config, terraform.workspace, local.workspace_config.default)

  # Common tags including workspace
  common_tags = {
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
    Workspace   = terraform.workspace
  }

  # Name prefix using workspace
  name_prefix = "myproject-${terraform.workspace}"
}

# ============================================
# RESOURCES USING WORKSPACE
# ============================================

resource "aws_vpc" "main" {
  cidr_block = "10.${terraform.workspace == "prod" ? 2 : terraform.workspace == "stg" ? 1 : 0}.0.0/16"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# resource "aws_instance" "app" {
#   count = local.config.instance_count
#
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = local.config.instance_type
#
#   tags = merge(local.common_tags, {
#     Name = "${local.name_prefix}-app-${count.index + 1}"
#   })
# }

# Conditional RDS based on workspace
# resource "aws_db_instance" "main" {
#   count = local.config.enable_rds ? 1 : 0
#   
#   identifier = "${local.name_prefix}-db"
#   # ... other config
# }

# ============================================
# OUTPUTS
# ============================================

output "current_workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "environment" {
  description = "Environment name from workspace"
  value       = local.environment
}

output "workspace_config" {
  description = "Configuration for current workspace"
  value       = local.config
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

# ============================================
# WORKSPACE COMMANDS REFERENCE
# ============================================

# List workspaces:
# terraform workspace list

# Create new workspace:
# terraform workspace new dev
# terraform workspace new stg
# terraform workspace new prod

# Select workspace:
# terraform workspace select dev
# terraform workspace select prod

# Show current workspace:
# terraform workspace show

# Delete workspace (must not be current):
# terraform workspace select default
# terraform workspace delete dev

# ============================================
# WORKSPACE VS SEPARATE DIRECTORIES
# ============================================

# WORKSPACES are good when:
# - Same infrastructure, different environments
# - Environments have same structure but different sizes
# - Want to use single codebase
# - State isolation is sufficient

# SEPARATE DIRECTORIES are better when:
# - Environments have significantly different resources
# - Different teams manage different environments
# - Need different Terraform versions per environment
# - Want complete isolation (including code changes)

# ============================================
# WORKSPACE-AWARE BACKEND STATE PATHS
# ============================================

# With workspace_key_prefix = "env":
# 
# default workspace:
#   s3://bucket/workspaces/terraform.tfstate
#
# dev workspace:
#   s3://bucket/workspaces/env:/dev/terraform.tfstate
#
# prod workspace:
#   s3://bucket/workspaces/env:/prod/terraform.tfstate
