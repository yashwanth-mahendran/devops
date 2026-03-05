# ============================================
# TERRAFORM STATE MANAGEMENT GUIDE
# ============================================

This guide covers essential state management operations.

---

## State Commands Reference

### Viewing State

```bash
# List all resources in state
terraform state list

# Show specific resource details
terraform state show aws_instance.web

# Show full state (JSON)
terraform show -json | jq

# Pull remote state
terraform state pull > state.json
```

---

## Moving Resources (Refactoring)

### Rename a Resource

```bash
# Resource renamed in code from aws_instance.web to aws_instance.app
terraform state mv aws_instance.web aws_instance.app
```

### Move to Module

```bash
# Moving resource into a module
terraform state mv aws_instance.web module.compute.aws_instance.web
```

### Move Between Modules

```bash
# Moving from one module to another
terraform state mv module.old.aws_instance.web module.new.aws_instance.web
```

---

## Importing Existing Resources

### Basic Import

```bash
# Import existing EC2 instance
terraform import aws_instance.imported i-1234567890abcdef0

# Import VPC
terraform import aws_vpc.main vpc-12345678

# Import S3 bucket
terraform import aws_s3_bucket.data my-existing-bucket

# Import RDS
terraform import aws_db_instance.main my-database
```

### Import with Module

```bash
terraform import module.vpc.aws_vpc.main vpc-12345678
```

### Import with Count/For_each

```bash
# With count
terraform import 'aws_instance.web[0]' i-1234567890

# With for_each
terraform import 'aws_instance.web["web1"]' i-1234567890
```

---

## Removing from State

### Remove Without Destroying

```bash
# Remove resource from state (resource still exists in AWS)
terraform state rm aws_instance.orphaned

# Remove module
terraform state rm module.old_module

# Remove with confirmation bypass
terraform state rm -lock=false aws_instance.orphaned
```

### Use Cases

- Resource will be managed elsewhere
- Resource was created manually and doesn't need management anymore
- Cleaning up state after failed operations

---

## Replacing Resources

### Force Replacement

```bash
# Taint (deprecated in 1.0+)
terraform taint aws_instance.web

# Replace (preferred method)
terraform apply -replace=aws_instance.web

# Replace multiple
terraform apply -replace=aws_instance.web -replace=aws_ebs_volume.data
```

---

## State Recovery

### Recover from State Issues

```bash
# Force unlock (use with caution!)
terraform force-unlock LOCK_ID

# Pull and push state
terraform state pull > backup.tfstate
# Fix issues...
terraform state push backup.tfstate
```

### Rollback Using Versioned State

```bash
# S3 bucket versioning allows state recovery
aws s3api list-object-versions --bucket my-terraform-state --prefix path/to/terraform.tfstate

# Download previous version
aws s3api get-object --bucket my-terraform-state --key path/to/terraform.tfstate --version-id ABC123 recovered.tfstate

# Push recovered state
terraform state push recovered.tfstate
```

---

## State File Structure

```json
{
  "version": 4,
  "terraform_version": "1.5.0",
  "serial": 10,
  "lineage": "abc123-...",
  "outputs": {
    "vpc_id": {
      "value": "vpc-12345678",
      "type": "string"
    }
  },
  "resources": [
    {
      "mode": "managed",
      "type": "aws_vpc",
      "name": "main",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 1,
          "attributes": {
            "id": "vpc-12345678",
            "cidr_block": "10.0.0.0/16"
          }
        }
      ]
    }
  ]
}
```

---

## Moved Block (Terraform 1.1+)

Instead of `terraform state mv`, use moved blocks in code:

```hcl
# Declare the move in configuration
moved {
  from = aws_instance.web
  to   = aws_instance.app
}

moved {
  from = aws_instance.old
  to   = module.compute.aws_instance.main
}

# After apply, can remove moved blocks
```

Benefits:
- Tracked in version control
- Can be reviewed in PR
- Works with CI/CD pipelines

---

## Import Block (Terraform 1.5+)

Generate configuration from existing resources:

```hcl
# Declare import in configuration
import {
  to = aws_instance.imported
  id = "i-1234567890abcdef0"
}

# Generate configuration
terraform plan -generate-config-out=generated.tf
```

Benefits:
- Configuration is generated automatically
- Reduces manual work
- Less error-prone

---

## Safety Best Practices

1. **Always backup state before operations**
   ```bash
   terraform state pull > backup-$(date +%Y%m%d).tfstate
   ```

2. **Use -lock=false carefully** - only when certain no one else is operating

3. **Test state operations in non-production first**

4. **Enable state versioning in S3 backend**

5. **Review plan carefully after state operations**
   ```bash
   terraform plan  # Should show no changes after correct state move
   ```
