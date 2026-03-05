# ============================================
# EC2 MODULE - Variables
# ============================================

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "instance_name" {
  description = "Instance name suffix"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of instances"
  type        = number
  default     = 1
}

variable "ami_id" {
  description = "AMI ID (uses latest Amazon Linux 2 if not specified)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "key_name" {
  description = "SSH key name"
  type        = string
  default     = null
}

variable "instance_profile" {
  description = "IAM instance profile"
  type        = string
  default     = null
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "Root volume type"
  type        = string
  default     = "gp3"
}

variable "encrypted" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

variable "delete_on_termination" {
  description = "Delete root volume on termination"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = false
}

variable "create_data_volume" {
  description = "Create additional data volume"
  type        = bool
  default     = false
}

variable "data_volume_size" {
  description = "Data volume size in GB"
  type        = number
  default     = 50
}

variable "data_volume_type" {
  description = "Data volume type"
  type        = string
  default     = "gp3"
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
