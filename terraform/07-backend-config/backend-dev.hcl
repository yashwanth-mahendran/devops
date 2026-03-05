# ============================================
# BACKEND CONFIGURATION - DEV ENVIRONMENT
# ============================================
# Usage: terraform init -backend-config=backend-dev.hcl

bucket         = "mycompany-terraform-state-dev"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-state-lock-dev"

# Optional: Use workspace prefix
# workspace_key_prefix = "workspaces"
