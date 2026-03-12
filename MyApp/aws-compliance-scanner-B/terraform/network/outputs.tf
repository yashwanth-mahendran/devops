################################################################################
# VPC Outputs
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

################################################################################
# Subnet Outputs
################################################################################

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB)"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EKS nodes)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs (for VPC endpoints)"
  value       = aws_subnet.isolated[*].id
}

output "isolated_subnet_cidrs" {
  description = "Isolated subnet CIDR blocks"
  value       = aws_subnet.isolated[*].cidr_block
}

################################################################################
# Security Group Outputs
################################################################################

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS control plane"
  value       = aws_security_group.eks_cluster.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "lambda_security_group_id" {
  description = "Security group ID for Lambda functions"
  value       = aws_security_group.lambda.id
}

################################################################################
# VPC Endpoint Outputs
################################################################################

output "vpc_endpoint_s3_id" {
  description = "S3 Gateway VPC endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_dynamodb_id" {
  description = "DynamoDB Gateway VPC endpoint ID"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "vpc_endpoints_interface" {
  description = "Interface VPC endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

################################################################################
# NAT Gateway Outputs
################################################################################

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway Elastic IPs"
  value       = aws_eip.nat[*].public_ip
}

################################################################################
# ALB Outputs
################################################################################

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID"
  value       = aws_lb.main.zone_id
}

output "alb_target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.main.arn
}

output "https_listener_arn" {
  description = "HTTPS listener ARN"
  value       = aws_lb_listener.https.arn
}

################################################################################
# WAF Outputs
################################################################################

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

################################################################################
# Certificate Outputs
################################################################################

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = var.create_certificate ? aws_acm_certificate.main[0].arn : var.certificate_arn
}

################################################################################
# Flow Logs
################################################################################

output "vpc_flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

################################################################################
# Availability Zones
################################################################################

output "availability_zones" {
  description = "Availability zones used"
  value       = local.azs
}
