# ============================================
# TERRAFORM DATA SOURCES - Complete Examples
# ============================================

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
  region = "us-east-1"
}

# ============================================
# AWS ACCOUNT & REGION DATA
# ============================================

# Current AWS account info
data "aws_caller_identity" "current" {}

# Current region
data "aws_region" "current" {}

# Available AZs
data "aws_availability_zones" "available" {
  state = "available"

  # Filter out Local Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ============================================
# AMI DATA SOURCES
# ============================================

# Latest Amazon Linux 2
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Latest Ubuntu 22.04
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Custom/Shared AMI
data "aws_ami" "custom" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Application"
    values = ["myapp"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ============================================
# VPC DATA SOURCES
# ============================================

# Existing VPC by tag
data "aws_vpc" "existing" {
  count = 0  # Enable when needed

  tags = {
    Name = "production-vpc"
  }
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Subnets in a VPC
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  tags = {
    Type = "Private"
  }
}

# Single subnet by ID
# data "aws_subnet" "selected" {
#   id = "subnet-12345678"
# }

# ============================================
# SECURITY GROUP DATA
# ============================================

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "group-name"
    values = ["default"]
  }
}

# ============================================
# IAM DATA SOURCES
# ============================================

# AWS managed policy
data "aws_iam_policy" "admin" {
  name = "AdministratorAccess"
}

data "aws_iam_policy" "ssm" {
  name = "AmazonSSMManagedInstanceCore"
}

# IAM policy document (for creating policies)
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid    = "S3ReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::my-bucket",
      "arn:aws:s3:::my-bucket/*"
    ]
  }
}

# ============================================
# SECRETS/PARAMETERS DATA
# ============================================

# SSM Parameter
data "aws_ssm_parameter" "db_host" {
  count = 0  # Enable when parameter exists
  name  = "/prod/database/host"
}

# Secrets Manager
data "aws_secretsmanager_secret" "db_creds" {
  count = 0  # Enable when secret exists
  name  = "prod/db/credentials"
}

# ============================================
# S3 DATA SOURCES
# ============================================

data "aws_s3_bucket" "logs" {
  count  = 0  # Enable when bucket exists
  bucket = "my-logs-bucket"
}

# ============================================
# ROUTE53 DATA SOURCES
# ============================================

data "aws_route53_zone" "main" {
  count        = 0  # Enable when zone exists
  name         = "example.com."
  private_zone = false
}

# ============================================
# KMS DATA SOURCES
# ============================================

# AWS managed key
data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

data "aws_kms_alias" "rds" {
  name = "alias/aws/rds"
}

# ============================================
# EKS DATA SOURCES
# ============================================

data "aws_eks_cluster" "existing" {
  count = 0  # Enable when cluster exists
  name  = "my-cluster"
}

data "aws_eks_cluster_auth" "existing" {
  count = 0  # Enable when cluster exists
  name  = "my-cluster"
}

# ============================================
# REMOTE STATE DATA SOURCE
# ============================================

# Read outputs from another Terraform state
data "terraform_remote_state" "vpc" {
  count   = 0  # Enable when state exists
  backend = "s3"

  config = {
    bucket = "my-terraform-state"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# Usage: data.terraform_remote_state.vpc[0].outputs.vpc_id

# ============================================
# HTTP DATA SOURCE
# ============================================

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

# ============================================
# LOCAL FILE DATA SOURCE
# ============================================

data "local_file" "ssh_key" {
  count    = 0  # Enable when file exists
  filename = "${path.module}/keys/id_rsa.pub"
}

# ============================================
# TEMPLATE FILE DATA SOURCE
# ============================================

data "template_file" "user_data" {
  template = file("${path.module}/templates/user_data.sh")
  
  vars = {
    environment = "production"
    app_name    = "myapp"
  }
}

# ============================================
# OUTPUTS
# ============================================

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = data.aws_region.current.name
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

output "amazon_linux_ami_id" {
  value = data.aws_ami.amazon_linux_2.id
}

output "ubuntu_ami_id" {
  value = data.aws_ami.ubuntu.id
}

output "default_vpc_id" {
  value = data.aws_vpc.default.id
}

output "my_public_ip" {
  value = trimspace(data.http.my_ip.response_body)
}

output "admin_policy_arn" {
  value = data.aws_iam_policy.admin.arn
}
