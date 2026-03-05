# ============================================
# BACKEND CONFIGURATION - PRODUCTION ENVIRONMENT
# ============================================
# Usage: terraform init -backend-config=backend-prod.hcl

bucket         = "mycompany-terraform-state-prod"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-state-lock-prod"

# Production: Use specific role for elevated security
# role_arn = "arn:aws:iam::PROD_ACCOUNT_ID:role/TerraformStateAccess"

# Additional security for production
# skip_metadata_api_check = true
