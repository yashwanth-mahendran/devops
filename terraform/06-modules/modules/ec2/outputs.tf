# ============================================
# EC2 MODULE - Outputs
# ============================================

output "instance_ids" {
  description = "List of instance IDs"
  value       = aws_instance.main[*].id
}

output "public_ips" {
  description = "List of public IP addresses"
  value       = aws_instance.main[*].public_ip
}

output "private_ips" {
  description = "List of private IP addresses"
  value       = aws_instance.main[*].private_ip
}

output "availability_zones" {
  description = "Availability zones of instances"
  value       = aws_instance.main[*].availability_zone
}

output "instance_arns" {
  description = "List of instance ARNs"
  value       = aws_instance.main[*].arn
}
