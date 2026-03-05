# ============================================
# EC2 MODULE - Main Configuration
# ============================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================
# DATA SOURCES
# ============================================
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ============================================
# LOCAL VALUES
# ============================================
locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.instance_name}"
  ami_id      = coalesce(var.ami_id, data.aws_ami.amazon_linux.id)
  
  common_tags = merge(var.tags, {
    Module = "ec2"
  })
}

# ============================================
# EC2 INSTANCES
# ============================================
resource "aws_instance" "main" {
  count = var.instance_count

  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = var.encrypted
    delete_on_termination = var.delete_on_termination
  }

  user_data = var.user_data

  monitoring = var.enable_monitoring

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${count.index + 1}"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ============================================
# EBS VOLUMES (Optional)
# ============================================
resource "aws_ebs_volume" "data" {
  count = var.create_data_volume ? var.instance_count : 0

  availability_zone = aws_instance.main[count.index].availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = var.encrypted

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-${count.index + 1}"
  })
}

resource "aws_volume_attachment" "data" {
  count = var.create_data_volume ? var.instance_count : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.main[count.index].id
}
