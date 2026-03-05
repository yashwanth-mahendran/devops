# ============================================
# PRODUCTION ENVIRONMENT VARIABLES
# ============================================
# Usage: terraform plan -var-file="prod.tfvars"

# Core settings
aws_region   = "us-east-1"
project_name = "myproject"
environment  = "prod"
cost_center  = "engineering-prod"

additional_tags = {
  Team        = "Platform"
  Owner       = "platform-team@example.com"
  Purpose     = "Production Environment"
  Compliance  = "SOC2"
  DataClass   = "Confidential"
}

# Network settings
vpc_cidr     = "10.2.0.0/16"  # Production CIDR
subnet_count = 3              # 3 AZs for production

allowed_cidr_blocks = ["10.0.0.0/8"]  # Internal only - use ALB for public
allowed_ports       = [443]            # HTTPS only

# Compute settings
instance_count           = 3   # Multi-AZ deployment
instance_type_override   = "t3.large"  # Override to larger instance
root_volume_size         = 50
enable_encryption        = true

# Database settings
create_rds           = true
db_engine            = "postgres"
db_engine_version    = "15.4"
db_instance_class    = "db.r6g.large"  # Production-grade instance
db_allocated_storage = 200
db_name              = "proddb"
db_username          = "prodadmin"
# db_password - MUST be from AWS Secrets Manager

# Feature flags
enable_monitoring = true
enable_logging    = true
enable_backup     = true
