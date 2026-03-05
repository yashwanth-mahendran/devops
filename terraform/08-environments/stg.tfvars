# ============================================
# STAGING ENVIRONMENT VARIABLES
# ============================================
# Usage: terraform plan -var-file="stg.tfvars"

# Core settings
aws_region   = "us-east-1"
project_name = "myproject"
environment  = "stg"
cost_center  = "engineering-stg"

additional_tags = {
  Team    = "QA"
  Owner   = "qa-team@example.com"
  Purpose = "Staging/QA Environment"
}

# Network settings
vpc_cidr     = "10.1.0.0/16"  # Different CIDR for staging
subnet_count = 2

allowed_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]  # Internal only
allowed_ports       = [80, 443]

# Compute settings
instance_count      = 2  # More instances for testing
root_volume_size    = 30
enable_encryption   = true

# Database settings  
create_rds           = true
db_engine            = "postgres"
db_engine_version    = "15.4"
db_instance_class    = "db.t3.small"
db_allocated_storage = 50
db_name              = "stgdb"
db_username          = "stgadmin"
# db_password provided via AWS Secrets Manager or environment variable

# Feature flags
enable_monitoring = true
enable_logging    = true
enable_backup     = true
