# ============================================
# RDS MODULE - Main Configuration
# ============================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ============================================
# LOCAL VALUES
# ============================================
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = merge(var.tags, {
    Module = "rds"
  })
}

# ============================================
# RANDOM PASSWORD
# ============================================
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ============================================
# DB SUBNET GROUP
# ============================================
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Database subnet group for ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# ============================================
# SECURITY GROUP
# ============================================
resource "aws_security_group" "db" {
  count = var.create_security_group ? 1 : 0

  name        = "${local.name_prefix}-db-sg"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.security_group_ids
    description     = "Database access from application"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-sg"
  })
}

# ============================================
# RDS INSTANCE
# ============================================
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  # Engine configuration
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type         = var.storage_type
  storage_encrypted    = true
  kms_key_id           = var.kms_key_id

  # Database configuration
  db_name  = var.database_name
  username = var.master_username
  password = coalesce(var.master_password, random_password.master.result)
  port     = var.port

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.create_security_group ? [aws_security_group.db[0].id] : var.security_group_ids
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Backup configuration
  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  skip_final_snapshot     = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-final-snapshot"
  copy_tags_to_snapshot   = true

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.monitoring_interval
  monitoring_role_arn          = var.monitoring_role_arn

  # Other settings
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  deletion_protection         = var.deletion_protection
  apply_immediately           = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db"
  })
}

# ============================================
# STORE PASSWORD IN SECRETS MANAGER
# ============================================
resource "aws_secretsmanager_secret" "db_credentials" {
  count = var.store_credentials_in_secrets_manager ? 1 : 0

  name        = "${local.name_prefix}/db-credentials"
  description = "RDS credentials for ${var.environment}"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  count = var.store_credentials_in_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_credentials[0].id
  secret_string = jsonencode({
    username = var.master_username
    password = coalesce(var.master_password, random_password.master.result)
    engine   = var.engine
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.database_name
  })
}
