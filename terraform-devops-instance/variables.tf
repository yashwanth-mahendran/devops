variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "devops-instance"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "us-west-2a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Name for the SSH key pair (will be auto-generated)"
  type        = string
  default     = "devops-key"
}

# Tool Versions (Latest Stable)
variable "terraform_version" {
  description = "Terraform version"
  type        = string
  default     = "1.10.3"
}

variable "kubectl_version" {
  description = "kubectl version (use 'latest' for latest stable)"
  type        = string
  default     = "latest"
}

variable "helm_version" {
  description = "Helm version (use 'latest' for latest stable)"
  type        = string
  default     = "latest"
}

variable "docker_compose_version" {
  description = "Docker Compose version (use 'latest' for latest stable)"
  type        = string
  default     = "latest"
}

variable "maven_version" {
  description = "Maven version"
  type        = string
  default     = "3.9.9"
}

variable "nodejs_version" {
  description = "Node.js major version"
  type        = string
  default     = "22"
}

variable "python_version" {
  description = "Python version"
  type        = string
  default     = "3.12"
}

variable "java_version" {
  description = "Java version (Amazon Corretto)"
  type        = string
  default     = "21"
}

variable "trivy_version" {
  description = "Trivy version"
  type        = string
  default     = "0.58.1"
}

variable "eksctl_version" {
  description = "eksctl version (use 'latest' for latest stable)"
  type        = string
  default     = "latest"
}

variable "k9s_version" {
  description = "k9s version (use 'latest' for latest stable)"
  type        = string
  default     = "latest"
}

variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 1
}
