# ============================================
# SECRETS MANAGEMENT BEST PRACTICES
# ============================================

# ============================================
# DO's
# ============================================

# ✅ 1. Use sensitive = true for secret variables
variable "api_key" {
  description = "API key"
  type        = string
  sensitive   = true
}

# ✅ 2. Generate random passwords
resource "random_password" "secure_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 4
}

# ✅ 3. Use AWS Secrets Manager for production
resource "aws_secretsmanager_secret" "api_credentials" {
  name        = "prod/api/credentials"
  description = "API credentials"
  
  # Enable automatic rotation
  # rotation_lambda_arn = aws_lambda_function.rotate_secret.arn
  # rotation_rules {
  #   automatically_after_days = 30
  # }
}

# ✅ 4. Use environment variables
# export TF_VAR_db_password="secure-password"
# export AWS_ACCESS_KEY_ID="your-key"
# export AWS_SECRET_ACCESS_KEY="your-secret"

# ✅ 5. Use .gitignore to exclude sensitive files
# Add to .gitignore:
# *.tfvars
# !*.tfvars.example
# .terraform/
# *.tfstate
# *.tfstate.*

# ============================================
# DON'Ts
# ============================================

# ❌ NEVER hardcode secrets
# variable "db_password" {
#   default = "mysecretpassword123"  # NEVER DO THIS!
# }

# ❌ NEVER commit secrets to git
# terraform.tfvars with secrets should be in .gitignore

# ❌ NEVER output secrets without sensitive flag
# output "password" {
#   value = var.db_password  # Missing sensitive = true!
# }

# ❌ NEVER store secrets in state without encryption
# Always use encrypted backend (S3 with KMS)

# ============================================
# SECRETS FILE EXAMPLE (.tfvars.example)
# ============================================
# Create a template file that's safe to commit
# Copy to .tfvars and fill in actual values

# Example: secrets.tfvars.example
# db_password = "REPLACE_WITH_ACTUAL_PASSWORD"
# api_key     = "REPLACE_WITH_ACTUAL_API_KEY"

# ============================================
# RUNTIME SECRET RETRIEVAL PATTERN
# ============================================

# Pattern 1: Read from Secrets Manager at deploy time
data "aws_secretsmanager_secret_version" "runtime_secret" {
  count     = 0  # Enable when secret exists
  secret_id = "my-secret"
}

# Pattern 2: Pass secret ARN to application, let app fetch
# This is more secure as Terraform doesn't see the value
locals {
  # Application fetches secret at runtime using this ARN
  # secret_arn_for_app = aws_secretsmanager_secret.my_secret.arn
}

# Pattern 3: Use IAM roles for secret access
# Application assumes role and fetches secrets via SDK

# ============================================
# SECRET ROTATION PATTERN
# ============================================

# Lambda function for rotating secrets
# resource "aws_lambda_function" "rotate_secret" {
#   filename         = "rotation_lambda.zip"
#   function_name    = "secret-rotation"
#   role             = aws_iam_role.rotation_role.arn
#   handler          = "index.handler"
#   runtime          = "python3.11"
# }

# Enable rotation on secret
# resource "aws_secretsmanager_secret_rotation" "example" {
#   secret_id           = aws_secretsmanager_secret.example.id
#   rotation_lambda_arn = aws_lambda_function.rotate_secret.arn
#   rotation_rules {
#     automatically_after_days = 30
#   }
# }
