# ============================================
# DEV ENVIRONMENT VARIABLES
# ============================================
# Usage: terraform plan -var-file="dev.tfvars"

# Core settings
aws_region   = "us-east-1"
project_name = "myproject"
environment  = "dev"
cost_center  = "engineering-dev"

additional_tags = {
  Team    = "Development"
  Owner   = "dev-team@example.com"
  Purpose = "Development Environment"
}

# Network settings
vpc_cidr    = "10.0.0.0/16"
subnet_count = 2

allowed_cidr_blocks = ["0.0.0.0/0"]  # More permissive for dev
allowed_ports       = [22, 80, 443, 3000, 8080]  # Extra ports for dev

# Compute settings
instance_count      = 1
root_volume_size    = 20
enable_encryption   = true

# Database settings
create_rds          = false  # No RDS in dev (use local or container)
db_name             = "devdb"
db_username         = "devadmin"
# db_password provided via environment variable or -var flag
# export TF_VAR_db_password="your-password"

# Feature flags
enable_monitoring = false  # Save costs in dev
enable_logging    = true
enable_backup     = false  # No backups needed in dev
