# ============================================
# TERRAFORM SECRETS MANAGEMENT
# ============================================
# Comprehensive guide to managing secrets in Terraform

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "dev"
}

variable "project_name" {
  default = "myproject"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ============================================
# METHOD 1: SENSITIVE VARIABLES
# ============================================
# Pass secrets via environment variables or -var flag
# These are marked as sensitive to hide from outputs

variable "db_password_from_var" {
  description = "Database password (sensitive)"
  type        = string
  sensitive   = true
  default     = ""  # Never hardcode secrets!
}

# Usage:
# export TF_VAR_db_password_from_var="your-secret-password"
# terraform plan

# ============================================
# METHOD 2: AWS SECRETS MANAGER
# ============================================
# Best practice for managing secrets in AWS

# Create a secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}/db-credentials"
  description             = "Database credentials for ${var.environment}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name        = "${local.name_prefix}-db-credentials"
    Environment = var.environment
  }
}

# Generate random password
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store secret value
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_password.result
    engine   = "postgres"
    host     = "db.example.com"
    port     = 5432
    dbname   = "appdb"
  })
}

# Read existing secret (data source)
data "aws_secretsmanager_secret" "existing_secret" {
  count = 0  # Set to 1 to enable
  name  = "existing-secret-name"
}

data "aws_secretsmanager_secret_version" "existing_secret" {
  count     = 0  # Set to 1 to enable
  secret_id = data.aws_secretsmanager_secret.existing_secret[0].id
}

# Parse secret JSON
locals {
  # Only parse if secret exists
  # db_creds = jsondecode(data.aws_secretsmanager_secret_version.existing_secret[0].secret_string)
  # db_username = local.db_creds.username
  # db_password = local.db_creds.password
}

# ============================================
# METHOD 3: AWS SSM PARAMETER STORE
# ============================================
# Good for configuration and secrets

# Create a SecureString parameter
resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.environment}/${var.project_name}/db/password"
  description = "Database password"
  type        = "SecureString"
  value       = random_password.db_password.result
  key_id      = aws_kms_key.secrets.arn  # Use custom KMS key

  tags = {
    Environment = var.environment
  }
}

# Create a String parameter (non-sensitive config)
resource "aws_ssm_parameter" "db_host" {
  name        = "/${var.environment}/${var.project_name}/db/host"
  description = "Database host"
  type        = "String"
  value       = "db.${var.environment}.example.com"

  tags = {
    Environment = var.environment
  }
}

# Create a StringList parameter
resource "aws_ssm_parameter" "allowed_ips" {
  name        = "/${var.environment}/${var.project_name}/allowed-ips"
  description = "List of allowed IPs"
  type        = "StringList"
  value       = "10.0.0.1,10.0.0.2,10.0.0.3"

  tags = {
    Environment = var.environment
  }
}

# Read existing SSM parameter
data "aws_ssm_parameter" "existing_param" {
  count = 0  # Set to 1 to enable
  name  = "/existing/parameter/path"
  # with_decryption = true  # Default for SecureString
}

# ============================================
# METHOD 4: KMS ENCRYPTION
# ============================================
# Create KMS key for secret encryption

resource "aws_kms_key" "secrets" {
  description             = "KMS key for ${var.environment} secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${local.name_prefix}-secrets-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

data "aws_caller_identity" "current" {}

# ============================================
# METHOD 5: HASHICORP VAULT (External)
# ============================================
# Example of reading secrets from HashiCorp Vault
# Uncomment to use

# provider "vault" {
#   address = "https://vault.example.com:8200"
#   # Auth configured via VAULT_TOKEN or other method
# }

# data "vault_generic_secret" "db_creds" {
#   path = "secret/data/${var.environment}/database"
# }

# locals {
#   vault_db_username = data.vault_generic_secret.db_creds.data["username"]
#   vault_db_password = data.vault_generic_secret.db_creds.data["password"]
# }

# ============================================
# METHOD 6: SOPS (Encrypted files)
# ============================================
# Use SOPS to encrypt files, decrypt with provider

# provider "sops" {}

# data "sops_file" "secrets" {
#   source_file = "secrets.enc.yaml"
# }

# locals {
#   sops_db_password = data.sops_file.secrets.data["db_password"]
# }

# ============================================
# IAM POLICY FOR SECRETS ACCESS
# ============================================
data "aws_iam_policy_document" "secrets_access" {
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.db_credentials.arn
    ]
  }

  statement {
    sid    = "SSMParameterAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/${var.project_name}/*"
    ]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      aws_kms_key.secrets.arn
    ]
  }
}

resource "aws_iam_policy" "secrets_access" {
  name        = "${local.name_prefix}-secrets-access"
  description = "Policy for accessing application secrets"
  policy      = data.aws_iam_policy_document.secrets_access.json
}

# ============================================
# EXAMPLE: EC2 WITH SECRET ACCESS
# ============================================
resource "aws_iam_role" "app_role" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app_role.name
}

# ============================================
# OUTPUTS (Sensitive values hidden)
# ============================================
output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "ssm_parameter_name" {
  description = "SSM parameter name"
  value       = aws_ssm_parameter.db_password.name
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.secrets.arn
}

output "generated_password" {
  description = "Generated password (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true  # Won't be shown in output
}

output "secrets_access_policy_arn" {
  description = "IAM policy for secrets access"
  value       = aws_iam_policy.secrets_access.arn
}

output "instance_profile_name" {
  description = "Instance profile with secrets access"
  value       = aws_iam_instance_profile.app_profile.name
}
