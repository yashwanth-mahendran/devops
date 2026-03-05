# ============================================
# RDS MODULE - Outputs
# ============================================

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS address (hostname)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "master_username" {
  description = "Master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "master_password" {
  description = "Master password"
  value       = coalesce(var.master_password, random_password.master.result)
  sensitive   = true
}

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = var.store_credentials_in_secrets_manager ? aws_secretsmanager_secret.db_credentials[0].arn : null
}

output "security_group_id" {
  description = "Security group ID"
  value       = var.create_security_group ? aws_security_group.db[0].id : null
}

output "connection_string" {
  description = "Database connection string"
  value       = "${var.engine}://${aws_db_instance.main.username}:PASSWORD@${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
  sensitive   = true
}
