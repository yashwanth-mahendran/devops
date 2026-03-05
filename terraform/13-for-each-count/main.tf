# ============================================
# TERRAFORM COUNT & FOR_EACH - Complete Examples
# ============================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================
# COUNT EXAMPLES
# ============================================

# Basic count - create N identical resources
variable "instance_count" {
  default = 3
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# resource "aws_instance" "count_example" {
#   count = var.instance_count
#
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = "t3.micro"
#
#   tags = {
#     Name = "instance-${count.index + 1}"
#   }
# }

# Count with conditional creation
variable "create_resource" {
  type    = bool
  default = true
}

resource "aws_sns_topic" "conditional" {
  count = var.create_resource ? 1 : 0
  name  = "conditional-topic"
}

# Count with list
variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

resource "aws_subnet" "count_list" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "subnet-${count.index + 1}"
    AZ   = var.availability_zones[count.index]
  }
}

# ============================================
# FOR_EACH EXAMPLES
# ============================================

# for_each with set of strings
variable "bucket_names" {
  type    = set(string)
  default = ["logs", "data", "backups"]
}

resource "aws_s3_bucket" "foreach_set" {
  for_each = var.bucket_names

  bucket = "myproject-${each.key}-${random_id.suffix.hex}"

  tags = {
    Name    = each.key
    Purpose = each.value  # Same as each.key for sets
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# for_each with map
variable "instances" {
  type = map(object({
    instance_type = string
    az            = string
  }))
  default = {
    web1 = {
      instance_type = "t3.micro"
      az            = "us-east-1a"
    }
    web2 = {
      instance_type = "t3.small"
      az            = "us-east-1b"
    }
    api1 = {
      instance_type = "t3.medium"
      az            = "us-east-1a"
    }
  }
}

# resource "aws_instance" "foreach_map" {
#   for_each = var.instances
#
#   ami               = data.aws_ami.amazon_linux.id
#   instance_type     = each.value.instance_type
#   availability_zone = each.value.az
#
#   tags = {
#     Name = each.key  # web1, web2, api1
#     Type = each.value.instance_type
#   }
# }

# for_each with conditional (filter)
variable "users" {
  type = map(object({
    name   = string
    role   = string
    active = bool
  }))
  default = {
    alice = { name = "Alice", role = "admin", active = true }
    bob   = { name = "Bob", role = "developer", active = true }
    carol = { name = "Carol", role = "admin", active = false }
  }
}

resource "aws_iam_user" "active_users" {
  for_each = {
    for username, user in var.users : username => user
    if user.active
  }

  name = each.key

  tags = {
    FullName = each.value.name
    Role     = each.value.role
  }
}

# for_each with list (convert to map)
variable "server_list" {
  type = list(object({
    name = string
    type = string
    port = number
  }))
  default = [
    { name = "web", type = "frontend", port = 80 },
    { name = "api", type = "backend", port = 8080 },
    { name = "db", type = "database", port = 5432 }
  ]
}

resource "aws_security_group_rule" "from_list" {
  for_each = { for server in var.server_list : server.name => server }

  type              = "ingress"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "${each.key} - ${each.value.type}"
}

# ============================================
# COUNT VS FOR_EACH COMPARISON
# ============================================

# COUNT: Good for identical resources, index-based
# - Resources addressed as resource.name[0], resource.name[1]
# - Removing middle element shifts all subsequent indexes
# - Simpler syntax for simple cases

# FOR_EACH: Good for unique resources, key-based
# - Resources addressed as resource.name["key"]
# - Removing an element only affects that specific resource
# - More stable when modifying collections
# - Required for maps and sets

# ============================================
# NESTED FOR_EACH (Flatten pattern)
# ============================================

variable "environments" {
  default = ["dev", "stg", "prod"]
}

variable "services" {
  default = ["web", "api", "worker"]
}

locals {
  # Create all combinations
  env_service_pairs = flatten([
    for env in var.environments : [
      for svc in var.services : {
        env     = env
        service = svc
        key     = "${env}-${svc}"
      }
    ]
  ])
}

resource "aws_cloudwatch_log_group" "services" {
  for_each = { for pair in local.env_service_pairs : pair.key => pair }

  name              = "/app/${each.value.env}/${each.value.service}"
  retention_in_days = each.value.env == "prod" ? 90 : 30

  tags = {
    Environment = each.value.env
    Service     = each.value.service
  }
}

# ============================================
# SUPPORTING RESOURCES
# ============================================

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "count-foreach-example"
  }
}

resource "aws_security_group" "main" {
  name   = "example-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ============================================
# OUTPUTS
# ============================================

# Output from count
output "subnet_ids" {
  value = aws_subnet.count_list[*].id
}

output "conditional_topic_arn" {
  value = var.create_resource ? aws_sns_topic.conditional[0].arn : "Not created"
}

# Output from for_each
output "bucket_names" {
  value = { for k, v in aws_s3_bucket.foreach_set : k => v.id }
}

output "active_users" {
  value = [for user in aws_iam_user.active_users : user.name]
}

output "log_group_names" {
  value = [for lg in aws_cloudwatch_log_group.services : lg.name]
}

# ============================================
# BEST PRACTICES
# ============================================

# 1. Use for_each over count when:
#    - Resources have unique identifiers
#    - Collection items might be added/removed
#    - You need stable references

# 2. Use count when:
#    - Creating identical resources
#    - Simple conditional creation (count = condition ? 1 : 0)
#    - Working with simple numeric iterations

# 3. Converting list to map for for_each:
#    { for item in list : item.unique_key => item }

# 4. Handling count-created resources:
#    - Access: resource.name[index]
#    - All: resource.name[*].attribute

# 5. Handling for_each-created resources:
#    - Access: resource.name["key"]
#    - All: [for k, v in resource.name : v.attribute]
