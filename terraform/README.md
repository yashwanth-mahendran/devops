# Terraform Concepts & Examples

A comprehensive guide to Terraform with practical examples covering all essential concepts.

---

## 📁 Folder Structure

```
terraform/
├── README.md                          # This file
├── 01-variables/                      # All variable types
│   ├── variables.tf                   # Variable definitions
│   ├── terraform.tfvars              # Default values
│   └── outputs.tf                     # Output examples
├── 02-conditions-expressions/         # Conditionals & expressions
│   ├── main.tf
│   ├── conditions.tf
│   └── expressions.tf
├── 03-resources/                      # Resource usage patterns
│   ├── main.tf
│   ├── ec2.tf
│   ├── s3.tf
│   ├── iam.tf
│   └── dependencies.tf
├── 04-data-sources/                   # Data source examples
│   ├── main.tf
│   └── data.tf
├── 05-locals/                         # Local values
│   └── main.tf
├── 06-modules/                        # Module patterns
│   ├── main.tf
│   └── modules/
│       ├── vpc/
│       ├── ec2/
│       └── rds/
├── 07-backend-config/                 # Backend configurations
│   ├── backend-dev.hcl
│   ├── backend-stg.hcl
│   ├── backend-prod.hcl
│   └── main.tf
├── 08-environments/                   # Multi-environment setup
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── dev.tfvars
│   ├── stg.tfvars
│   └── prod.tfvars
├── 09-secrets-management/             # Secret handling
│   ├── main.tf
│   ├── secrets.tf
│   └── aws-secrets-manager.tf
├── 10-state-management/               # State operations
│   └── README.md
├── 11-provisioners/                   # Provisioner examples
│   └── main.tf
├── 12-dynamic-blocks/                 # Dynamic blocks
│   └── main.tf
├── 13-for-each-count/                 # Loops and iteration
│   └── main.tf
├── 14-workspaces/                     # Workspace management
│   └── main.tf
└── 15-best-practices/                 # Best practices guide
    └── README.md
```

---

## 🚀 Quick Start

### Initialize Terraform

```bash
cd 01-variables
terraform init

# With specific backend config
terraform init -backend-config=backend-dev.hcl
```

### Plan and Apply

```bash
# Using default tfvars
terraform plan

# Using environment-specific tfvars
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"

# Auto-approve (use with caution)
terraform apply -auto-approve -var-file="dev.tfvars"
```

### Destroy Resources

```bash
terraform destroy -var-file="dev.tfvars"
```

---

## 📚 Concepts Covered

| Concept | Description |
|---------|-------------|
| Variables | All types: string, number, bool, list, map, set, object, tuple |
| Conditions | Ternary operators, null coalescing, validation rules |
| Expressions | For expressions, splat operators, dynamic blocks |
| Resources | AWS resources with best practices |
| Data Sources | Querying existing infrastructure |
| Locals | Computed local values |
| Modules | Reusable infrastructure components |
| Backend | Remote state with S3/DynamoDB |
| Environments | Dev/Stg/Prod configurations |
| Secrets | AWS Secrets Manager, SSM Parameter Store |
| State | Import, move, remove operations |
| Workspaces | Environment isolation |

---

## 🔧 Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured
- AWS credentials with appropriate permissions
