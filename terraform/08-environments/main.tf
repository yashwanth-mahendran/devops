# ============================================
# MULTI-ENVIRONMENT TERRAFORM CONFIGURATION
# ============================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configured via backend-*.hcl files
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
    }
  }
}

# ============================================
# LOCALS - Environment-specific configurations
# ============================================
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Environment-specific instance types
  instance_types = {
    dev  = "t3.micro"
    stg  = "t3.small"
    prod = "t3.medium"
  }

  # Select based on environment or use override
  instance_type = coalesce(
    var.instance_type_override,
    lookup(local.instance_types, var.environment, "t3.micro")
  )

  # Environment-specific replica counts
  is_production = var.environment == "prod"
  min_instances = local.is_production ? 2 : 1
  max_instances = local.is_production ? 10 : 3

  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ============================================
# DATA SOURCES
# ============================================
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ============================================
# VPC
# ============================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ============================================
# SUBNETS
# ============================================
resource "aws_subnet" "public" {
  count = var.subnet_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Type = "Public"
  }
}

resource "aws_subnet" "private" {
  count = var.subnet_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Type = "Private"
  }
}

# ============================================
# SECURITY GROUP
# ============================================
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Application security group"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

# ============================================
# EC2 INSTANCE
# ============================================
resource "aws_instance" "app" {
  count = var.instance_count

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = local.instance_type
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = var.enable_encryption
  }

  tags = {
    Name = "${local.name_prefix}-app-${count.index + 1}"
  }
}

# ============================================
# RDS (Only for stg and prod)
# ============================================
resource "aws_db_subnet_group" "main" {
  count = var.create_rds ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  count = var.create_rds ? 1 : 0

  identifier           = "${local.name_prefix}-db"
  engine               = var.db_engine
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  storage_encrypted    = true
  
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  
  db_subnet_group_name = aws_db_subnet_group.main[0].name
  multi_az             = local.is_production
  
  backup_retention_period = local.is_production ? 30 : 7
  skip_final_snapshot     = !local.is_production

  tags = {
    Name = "${local.name_prefix}-db"
  }
}

# ============================================
# OUTPUTS
# ============================================
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "instance_ids" {
  value = aws_instance.app[*].id
}

output "instance_public_ips" {
  value = aws_instance.app[*].public_ip
}

output "rds_endpoint" {
  value     = var.create_rds ? aws_db_instance.main[0].endpoint : "N/A"
  sensitive = false
}

output "environment_summary" {
  value = {
    environment    = var.environment
    instance_type  = local.instance_type
    instance_count = var.instance_count
    is_production  = local.is_production
  }
}
