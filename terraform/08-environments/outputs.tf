# ============================================
# ENVIRONMENT OUTPUTS
# ============================================

output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnets" {
  description = "Public subnet details"
  value = {
    ids  = aws_subnet.public[*].id
    cidrs = aws_subnet.public[*].cidr_block
    azs   = aws_subnet.public[*].availability_zone
  }
}

output "private_subnets" {
  description = "Private subnet details"
  value = {
    ids   = aws_subnet.private[*].id
    cidrs = aws_subnet.private[*].cidr_block
    azs   = aws_subnet.private[*].availability_zone
  }
}

output "app_security_group_id" {
  description = "Application security group ID"
  value       = aws_security_group.app.id
}

output "ec2_instances" {
  description = "EC2 instance details"
  value = [
    for idx, instance in aws_instance.app : {
      id         = instance.id
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      az         = instance.availability_zone
    }
  ]
}

output "rds_details" {
  description = "RDS instance details"
  value = var.create_rds ? {
    endpoint     = aws_db_instance.main[0].endpoint
    port         = aws_db_instance.main[0].port
    database     = aws_db_instance.main[0].db_name
    multi_az     = aws_db_instance.main[0].multi_az
  } : null
  sensitive = false
}

output "deployment_summary" {
  description = "Summary of deployment"
  value = <<-EOT
    
    ========================================
    DEPLOYMENT SUMMARY
    ========================================
    Environment:    ${var.environment}
    Project:        ${var.project_name}
    Region:         ${var.aws_region}
    VPC CIDR:       ${var.vpc_cidr}
    Instance Count: ${var.instance_count}
    RDS Created:    ${var.create_rds}
    ========================================
  EOT
}
