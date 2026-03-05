# ============================================
# TERRAFORM.TFVARS - Default Variable Values
# ============================================
# This file is automatically loaded by Terraform
# Override these values with environment-specific .tfvars files

# Basic variables
project_name      = "my-terraform-project"
environment       = "dev"
instance_count    = 2
disk_size_gb      = 50
enable_monitoring = true
create_dns_record = false

# List variables
availability_zones = ["us-east-1a", "us-east-1b"]
allowed_ports      = [22, 80, 443]

# Map variables
tags = {
  Project     = "TerraformDemo"
  Environment = "dev"
  Team        = "DevOps"
  ManagedBy   = "Terraform"
  CostCenter  = "Engineering"
}

ami_ids = {
  us-east-1 = "ami-0c55b159cbfafe1f0"
  us-west-2 = "ami-0892d3c7ee96c0bf7"
}

# Object variables
instance_config = {
  instance_type = "t3.small"
  ami_id        = "ami-0c55b159cbfafe1f0"
  volume_size   = 50
  encrypted     = true
}

vpc_config = {
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
      public            = true
    },
    {
      cidr_block        = "10.0.10.0/24"
      availability_zone = "us-east-1a"
      public            = false
    },
    {
      cidr_block        = "10.0.11.0/24"
      availability_zone = "us-east-1b"
      public            = false
    }
  ]
}

database_config = {
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.small"
  allocated_storage = 50
  multi_az          = false
  backup_retention  = 14
}

# Tuple variables
scaling_config = [2, 10, 4]

# Validation example variables
cidr_block     = "10.0.0.0/16"
email          = "devops@example.com"
s3_bucket_name = "my-unique-terraform-bucket-12345"
