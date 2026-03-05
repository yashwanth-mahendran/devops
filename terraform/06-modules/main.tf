# ============================================
# TERRAFORM MODULES - Main Configuration
# ============================================
# Demonstrates how to use and create modules

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

variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "dev"
}

variable "project_name" {
  default = "myproject"
}

# ============================================
# USING LOCAL MODULES
# ============================================

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = "10.0.0.0/16"
  
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  
  enable_nat_gateway = var.environment != "dev"
  single_nat_gateway = var.environment == "stg"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# EC2 Module
module "ec2_web" {
  source = "./modules/ec2"

  project_name  = var.project_name
  environment   = var.environment
  instance_name = "web"
  
  instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"
  instance_count = var.environment == "prod" ? 3 : 1
  
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.vpc.default_security_group_id]
  
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
  EOF

  tags = {
    Role = "WebServer"
  }

  # Module dependency
  depends_on = [module.vpc]
}

# RDS Module (only for stg/prod)
module "rds" {
  source = "./modules/rds"
  count  = var.environment != "dev" ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.environment == "prod" ? "db.r6g.large" : "db.t3.small"
  
  database_name  = "appdb"
  master_username = "dbadmin"
  
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.vpc.default_security_group_id]
  
  multi_az              = var.environment == "prod"
  backup_retention_days = var.environment == "prod" ? 30 : 7

  tags = {
    DataClassification = var.environment == "prod" ? "Confidential" : "Internal"
  }
}

# ============================================
# USING REGISTRY MODULES
# ============================================

# AWS VPC Module from Terraform Registry
# module "vpc_registry" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 5.0"
#
#   name = "${var.project_name}-${var.environment}-vpc"
#   cidr = "10.0.0.0/16"
#
#   azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
#   private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
#
#   enable_nat_gateway = true
#   single_nat_gateway = true
#
#   tags = {
#     Environment = var.environment
#   }
# }

# ============================================
# USING GITHUB MODULES
# ============================================

# module "github_module" {
#   source = "github.com/organization/terraform-module//path/to/module?ref=v1.0.0"
#   
#   variable1 = "value1"
# }

# ============================================
# USING S3 MODULES
# ============================================

# module "s3_module" {
#   source = "s3::https://s3-eu-west-1.amazonaws.com/bucket-name/module.zip"
# }

# ============================================
# OUTPUTS
# ============================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "web_instance_ids" {
  description = "Web server instance IDs"
  value       = module.ec2_web.instance_ids
}

output "web_public_ips" {
  description = "Web server public IPs"
  value       = module.ec2_web.public_ips
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = var.environment != "dev" ? module.rds[0].endpoint : "N/A"
}
