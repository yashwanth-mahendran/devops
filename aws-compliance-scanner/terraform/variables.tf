variable "aws_region"          { default = "us-east-1" }
variable "environment"         { default = "production" }
variable "project"             { default = "compliance-scanner" }
variable "eks_cluster_version" { default = "1.30" }
variable "eks_node_instance_types" {
  default = ["m5.xlarge", "m5.2xlarge"]
}
variable "eks_min_nodes"  { default = 3 }
variable "eks_max_nodes"  { default = 20 }
variable "eks_desired_nodes" { default = 3 }
variable "rds_instance_class" { default = "db.r6g.large" }
variable "rds_storage_gb"     { default = 100 }
variable "vpc_cidr"            { default = "10.0.0.0/16" }
variable "private_subnets"     { default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] }
variable "public_subnets"      { default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"] }
variable "lambda_timeout"      { default = 300 }
variable "lambda_memory_mb"    { default = 512 }
variable "ecr_image_tag_mutability" { default = "MUTABLE" }
variable "dr_secondary_region" { default = "us-west-2" }
