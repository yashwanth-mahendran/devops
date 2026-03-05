# ============================================
# BACKEND CONFIGURATION - STAGING ENVIRONMENT
# ============================================
# Usage: terraform init -backend-config=backend-stg.hcl

bucket         = "mycompany-terraform-state-stg"
key            = "stg/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-state-lock-stg"

# Optional: Assume role for cross-account access
# role_arn = "arn:aws:iam::STAGING_ACCOUNT_ID:role/TerraformStateAccess"
