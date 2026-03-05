# ============================================
# TERRAFORM OUTPUTS - Complete Examples
# ============================================
# Outputs expose values after terraform apply

# ============================================
# BASIC OUTPUT
# ============================================
output "project_name" {
  description = "The project name"
  value       = var.project_name
}

output "environment" {
  description = "Current environment"
  value       = var.environment
}

# ============================================
# SENSITIVE OUTPUT
# ============================================
output "db_password" {
  description = "Database password (sensitive)"
  value       = var.db_password
  sensitive   = true  # Hides value in CLI output
}

# ============================================
# COMPUTED OUTPUT
# ============================================
output "instance_name" {
  description = "Computed instance name"
  value       = "${var.project_name}-${var.environment}-instance"
}

# ============================================
# LIST OUTPUT
# ============================================
output "availability_zones" {
  description = "List of AZs"
  value       = var.availability_zones
}

output "first_az" {
  description = "First availability zone"
  value       = var.availability_zones[0]
}

# ============================================
# MAP OUTPUT
# ============================================
output "all_tags" {
  description = "All resource tags"
  value       = var.tags
}

output "specific_tag" {
  description = "Get specific tag value"
  value       = lookup(var.tags, "Project", "default-value")
}

# ============================================
# OBJECT OUTPUT
# ============================================
output "instance_config" {
  description = "Full instance configuration"
  value       = var.instance_config
}

output "instance_type" {
  description = "Instance type from config object"
  value       = var.instance_config.instance_type
}

# ============================================
# CONDITIONAL OUTPUT
# ============================================
output "monitoring_status" {
  description = "Monitoring status message"
  value       = var.enable_monitoring ? "Monitoring is ENABLED" : "Monitoring is DISABLED"
}

output "environment_tier" {
  description = "Environment tier based on name"
  value       = var.environment == "prod" ? "production" : "non-production"
}

# ============================================
# FORMATTED OUTPUT
# ============================================
output "scaling_summary" {
  description = "Scaling configuration summary"
  value       = "Min: ${var.scaling_config[0]}, Max: ${var.scaling_config[1]}, Desired: ${var.scaling_config[2]}"
}

output "subnets_summary" {
  description = "Summary of subnets"
  value = [
    for subnet in var.vpc_config.subnets : {
      cidr   = subnet.cidr_block
      az     = subnet.availability_zone
      type   = subnet.public ? "public" : "private"
    }
  ]
}

# ============================================
# JSON OUTPUT (useful for scripting)
# ============================================
output "config_json" {
  description = "Configuration as JSON"
  value       = jsonencode(var.vpc_config)
}

# ============================================
# DEPENDS_ON OUTPUT (rare but useful)
# ============================================
# output "final_status" {
#   description = "Status after resource creation"
#   value       = "Resources created successfully"
#   depends_on  = [aws_instance.example]
# }

# ============================================
# PRECONDITION OUTPUT (Terraform 1.2+)
# ============================================
output "validated_environment" {
  description = "Validated environment"
  value       = var.environment

  precondition {
    condition     = var.environment != ""
    error_message = "Environment cannot be empty."
  }
}
