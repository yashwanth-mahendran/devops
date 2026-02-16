output "instance_id" {
  description = "EC2 instance IDs"
  value       = aws_instance.devops[*].id
}

output "instance_public_ip" {
  description = "Public IP addresses"
  value       = aws_instance.devops[*].public_ip
}

output "instance_public_dns" {
  description = "Public DNS names"
  value       = aws_instance.devops[*].public_dns
}

output "ssh_command" {
  description = "SSH commands to connect"
  value       = [for i, instance in aws_instance.devops : "ssh -i ${var.key_name}.pem ec2-user@${instance.public_ip}"]
}

output "ssm_connect_command" {
  description = "AWS SSM Session Manager connect commands"
  value       = [for i, instance in aws_instance.devops : "aws ssm start-session --target ${instance.id} --region ${var.aws_region}"]
}

output "private_key_path" {
  description = "Path to private key file"
  value       = "${path.module}/${var.key_name}.pem"
}

output "key_pair_name" {
  description = "AWS key pair name"
  value       = aws_key_pair.devops.key_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for SSM sessions"
  value       = aws_cloudwatch_log_group.ssm_sessions.name
}

output "ssm_document_name" {
  description = "SSM document name for session preferences"
  value       = aws_ssm_document.session_manager_prefs.name
}

output "ssm_parameters" {
  description = "SSM parameter names for package repositories"
  value = {
    devops_packages      = aws_ssm_parameter.devops_packages.name
    mlops_packages       = aws_ssm_parameter.mlops_packages.name
    languages            = aws_ssm_parameter.programming_languages.name
    mlops_install_script = aws_ssm_parameter.installation_script.name
  }
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Subnet ID"
  value       = aws_subnet.public.id
}

output "instance_names" {
  description = "Instance names"
  value       = [for i, instance in aws_instance.devops : "${var.project_name}-instance-${i + 1}"]
}
