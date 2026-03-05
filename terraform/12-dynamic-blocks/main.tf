# ============================================
# TERRAFORM DYNAMIC BLOCKS - Complete Examples
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

variable "environment" {
  default = "dev"
}

# ============================================
# EXAMPLE 1: SECURITY GROUP WITH DYNAMIC RULES
# ============================================

variable "ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP"
    },
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS"
    },
    {
      port        = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "SSH from internal"
    }
  ]
}

resource "aws_security_group" "dynamic_example" {
  name        = "dynamic-sg-example"
  description = "Security group with dynamic blocks"

  # Dynamic ingress block
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  # Dynamic with iterator rename
  dynamic "egress" {
    for_each = [443, 80]
    iterator = port
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Outbound port ${port.value}"
    }
  }

  # Static egress for all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dynamic-sg-example"
  }
}

# ============================================
# EXAMPLE 2: CONDITIONAL DYNAMIC BLOCKS
# ============================================

variable "enable_https" {
  type    = bool
  default = true
}

variable "enable_ssh" {
  type    = bool
  default = false
}

locals {
  # Build rules conditionally
  conditional_rules = concat(
    # Always include HTTP
    [
      {
        port        = 80
        cidr_blocks = ["0.0.0.0/0"]
        description = "HTTP"
      }
    ],
    # Conditionally include HTTPS
    var.enable_https ? [
      {
        port        = 443
        cidr_blocks = ["0.0.0.0/0"]
        description = "HTTPS"
      }
    ] : [],
    # Conditionally include SSH
    var.enable_ssh ? [
      {
        port        = 22
        cidr_blocks = ["10.0.0.0/8"]
        description = "SSH"
      }
    ] : []
  )
}

resource "aws_security_group" "conditional_dynamic" {
  name = "conditional-dynamic-sg"

  dynamic "ingress" {
    for_each = local.conditional_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ============================================
# EXAMPLE 3: IAM POLICY WITH DYNAMIC STATEMENTS
# ============================================

variable "s3_buckets" {
  description = "S3 buckets to grant access to"
  type        = list(string)
  default     = ["bucket1", "bucket2", "bucket3"]
}

variable "allowed_actions" {
  description = "S3 actions to allow"
  type        = list(string)
  default     = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
}

data "aws_iam_policy_document" "dynamic_policy" {
  # Dynamic statement for each bucket
  dynamic "statement" {
    for_each = var.s3_buckets
    content {
      sid    = "S3Access${title(statement.value)}"
      effect = "Allow"
      actions = var.allowed_actions
      resources = [
        "arn:aws:s3:::${statement.value}",
        "arn:aws:s3:::${statement.value}/*"
      ]
    }
  }

  # Static statement
  statement {
    sid    = "ListAllBuckets"
    effect = "Allow"
    actions = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }
}

# ============================================
# EXAMPLE 4: EBS VOLUMES WITH DYNAMIC BLOCKS
# ============================================

variable "ebs_volumes" {
  description = "EBS volumes to attach"
  type = list(object({
    device_name = string
    volume_size = number
    volume_type = string
    encrypted   = bool
  }))
  default = [
    {
      device_name = "/dev/sdf"
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
    },
    {
      device_name = "/dev/sdg"
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
    }
  ]
}

# data "aws_ami" "amazon_linux" {
#   most_recent = true
#   owners      = ["amazon"]
#   filter {
#     name   = "name"
#     values = ["amzn2-ami-hvm-*-x86_64-gp2"]
#   }
# }

# resource "aws_instance" "with_volumes" {
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = "t3.micro"
#
#   dynamic "ebs_block_device" {
#     for_each = var.ebs_volumes
#     content {
#       device_name           = ebs_block_device.value.device_name
#       volume_size           = ebs_block_device.value.volume_size
#       volume_type           = ebs_block_device.value.volume_type
#       encrypted             = ebs_block_device.value.encrypted
#       delete_on_termination = true
#     }
#   }
#
#   tags = {
#     Name = "instance-with-dynamic-volumes"
#   }
# }

# ============================================
# EXAMPLE 5: NESTED DYNAMIC BLOCKS
# ============================================

variable "load_balancer_config" {
  description = "Load balancer configuration"
  type = object({
    name = string
    listeners = list(object({
      port     = number
      protocol = string
      actions = list(object({
        type         = string
        target_group = string
      }))
    }))
  })
  default = {
    name = "my-alb"
    listeners = [
      {
        port     = 80
        protocol = "HTTP"
        actions = [
          {
            type         = "forward"
            target_group = "web-tg"
          }
        ]
      },
      {
        port     = 443
        protocol = "HTTPS"
        actions = [
          {
            type         = "forward"
            target_group = "web-tg"
          }
        ]
      }
    ]
  }
}

# Example structure for nested dynamics (ALB)
# resource "aws_lb_listener" "example" {
#   for_each = { for l in var.load_balancer_config.listeners : l.port => l }
#
#   load_balancer_arn = aws_lb.main.arn
#   port              = each.value.port
#   protocol          = each.value.protocol
#
#   dynamic "default_action" {
#     for_each = each.value.actions
#     content {
#       type             = default_action.value.type
#       target_group_arn = aws_lb_target_group.main[default_action.value.target_group].arn
#     }
#   }
# }

# ============================================
# OUTPUTS
# ============================================

output "security_group_id" {
  value = aws_security_group.dynamic_example.id
}

output "conditional_rules_count" {
  value = length(local.conditional_rules)
}

output "dynamic_policy_json" {
  value = data.aws_iam_policy_document.dynamic_policy.json
}
