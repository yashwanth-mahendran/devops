# Terraform Best Practices Guide

Comprehensive best practices for production-grade Terraform code.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [State Management](#state-management)
3. [Variable Best Practices](#variable-best-practices)
4. [Resource Naming](#resource-naming)
5. [Security](#security)
6. [Code Organization](#code-organization)
7. [Module Development](#module-development)
8. [CI/CD Integration](#cicd-integration)
9. [Common Mistakes](#common-mistakes)
10. [Commands Reference](#commands-reference)

---

## Project Structure

### Recommended Layout

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── stg/
│   └── prod/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   ├── rds/
│   └── iam/
├── .gitignore
├── .terraform-version
└── README.md
```

### Alternative: Single Directory with Workspaces

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── backend.tf
├── dev.tfvars
├── stg.tfvars
├── prod.tfvars
└── modules/
```

---

## State Management

### ✅ DO's

```hcl
# Always use remote backend
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "project/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Use one state per environment
# dev:  project/dev/terraform.tfstate
# prod: project/prod/terraform.tfstate
```

### ❌ DON'Ts

```hcl
# Never use local state in production
terraform {
  backend "local" {}  # BAD!
}

# Never commit state files to git
# Add to .gitignore:
# *.tfstate
# *.tfstate.*
```

### State Commands

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_instance.web

# Move resource (refactoring)
terraform state mv aws_instance.old aws_instance.new

# Remove from state (without destroying)
terraform state rm aws_instance.orphaned

# Import existing resource
terraform import aws_instance.imported i-1234567890abcdef0

# Pull remote state locally
terraform state pull > state.json

# Push local state to remote
terraform state push state.json
```

---

## Variable Best Practices

### Validation

```hcl
variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "Environment must be dev, stg, or prod."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "Instance type must be t2 or t3 family."
  }
}
```

### Variable Precedence (lowest to highest)

1. Default value in variable block
2. `terraform.tfvars` file
3. `*.auto.tfvars` files (alphabetical)
4. `-var-file` flag
5. `-var` flag
6. `TF_VAR_*` environment variables

### Sensitive Variables

```hcl
variable "db_password" {
  type      = string
  sensitive = true  # Won't show in plans/logs
}

# Pass via environment variable
# export TF_VAR_db_password="secret"
```

---

## Resource Naming

### Naming Convention

```hcl
# Pattern: {project}-{environment}-{resource}-{identifier}

resource "aws_vpc" "main" {
  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_subnet" "public" {
  count = 2
  tags = {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"
  }
}
```

### Use Locals for Computed Names

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
  
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_instance" "web" {
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web"
    Role = "WebServer"
  })
}
```

---

## Security

### Never Store Secrets in Code

```hcl
# ❌ BAD
variable "db_password" {
  default = "mysecretpassword"
}

# ✅ GOOD - Use environment variables
# export TF_VAR_db_password="secret"

# ✅ GOOD - Use AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/password"
}
```

### Encrypt State

```hcl
terraform {
  backend "s3" {
    encrypt = true
    kms_key_id = "alias/terraform-state"
  }
}
```

### Use IAM Least Privilege

```hcl
# Create narrow IAM policies
data "aws_iam_policy_document" "s3_read_only" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::my-bucket/*"]
  }
}
```

---

## Code Organization

### File Structure

```
project/
├── main.tf          # Main resources and providers
├── variables.tf     # Variable declarations
├── outputs.tf       # Output declarations
├── locals.tf        # Local values
├── data.tf          # Data sources
├── versions.tf      # Required providers and versions
└── terraform.tfvars # Variable values (not in git for secrets)
```

### Pin Provider Versions

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Allow 5.x, not 6.x
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

---

## Module Development

### Module Structure

```
modules/vpc/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
└── examples/
    └── complete/
        └── main.tf
```

### Module Best Practices

```hcl
# 1. Use descriptive variable names
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC (e.g., 10.0.0.0/16)"
  type        = string
}

# 2. Provide sensible defaults
variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

# 3. Output all useful attributes
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# 4. Use version constraints when calling modules
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format Check
        run: terraform fmt -check

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve tfplan
```

### Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_docs
```

---

## Common Mistakes

### ❌ Mistake 1: Not Using Lifecycle Rules

```hcl
# BAD - AMI change causes replacement
resource "aws_instance" "web" {
  ami = data.aws_ami.latest.id
}

# GOOD - Ignore AMI changes
resource "aws_instance" "web" {
  ami = data.aws_ami.latest.id

  lifecycle {
    ignore_changes = [ami]
  }
}
```

### ❌ Mistake 2: Hardcoding Values

```hcl
# BAD
resource "aws_instance" "web" {
  instance_type = "t3.micro"  # Hardcoded
  ami           = "ami-12345678"  # Hardcoded
}

# GOOD
variable "instance_type" {
  default = "t3.micro"
}

data "aws_ami" "latest" {
  most_recent = true
  # ...
}

resource "aws_instance" "web" {
  instance_type = var.instance_type
  ami           = data.aws_ami.latest.id
}
```

### ❌ Mistake 3: Not Handling Count Edge Cases

```hcl
# Potential issue - accessing index 0 when count = 0
output "instance_id" {
  value = aws_instance.web[0].id  # Fails if count = 0
}

# GOOD - Check first
output "instance_id" {
  value = length(aws_instance.web) > 0 ? aws_instance.web[0].id : null
}

# BETTER - Use one() function
output "instance_id" {
  value = one(aws_instance.web[*].id)
}
```

---

## Commands Reference

### Essential Commands

```bash
# Initialize
terraform init
terraform init -upgrade  # Upgrade providers
terraform init -reconfigure  # Reinitialize backend

# Plan
terraform plan
terraform plan -out=tfplan  # Save plan
terraform plan -var-file="prod.tfvars"
terraform plan -target=aws_instance.web  # Plan specific resource

# Apply
terraform apply
terraform apply tfplan  # Apply saved plan
terraform apply -auto-approve  # Skip confirmation

# Destroy
terraform destroy
terraform destroy -target=aws_instance.web

# Format and Validate
terraform fmt  # Format code
terraform fmt -check  # Check formatting
terraform validate  # Validate configuration

# Output
terraform output
terraform output -json
terraform output vpc_id

# Refresh (sync state with actual infrastructure)
terraform refresh

# Graph (dependency visualization)
terraform graph | dot -Tpng > graph.png

# Console (interactive testing)
terraform console
> var.environment
> cidrsubnet("10.0.0.0/16", 8, 1)
```

### Debugging

```bash
# Enable debug logging
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform.log

# Log levels: TRACE, DEBUG, INFO, WARN, ERROR

# Crash log
# Check: crash.log in current directory
```

---

## .gitignore Template

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
crash.log
*.log

# Sensitive files
*.tfvars
!*.tfvars.example

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db
```

---

## Checklist

- [ ] Remote state configured with encryption
- [ ] State locking enabled (DynamoDB)
- [ ] Provider versions pinned
- [ ] Terraform version pinned
- [ ] Variables validated
- [ ] Secrets managed securely
- [ ] Resources tagged consistently
- [ ] Modules versioned
- [ ] Documentation up to date
- [ ] CI/CD pipeline configured
- [ ] Pre-commit hooks enabled
- [ ] .gitignore configured
