locals {
  lambda_checks = [
    "cfn-drift",
    "vpc-flow-logs",
    "audit-manager",
    "s3-encryption",
    "iam-mfa",
    "cloudtrail",
    "sg-unrestricted-ssh",
    "guardduty",
    "config-recorder",
    "secrets-manager-rotation",
    "ecr-image-scanning",
    "eks-cluster-logging",
    "rds-encryption",
    "ebs-encryption",
    "guardduty-enabled",
  ]
}

resource "aws_lambda_function" "compliance_checks" {
  for_each = toset(local.lambda_checks)

  function_name = "${var.project}-${each.key}"
  description   = "Compliance check: ${each.key}"
  role          = aws_iam_role.lambda_compliance.arn

  # Points to a pre-built bootstrap package; overwritten by CI deployments
  filename         = "${path.module}/../lambda-functions/${each.key}-check/${each.key}.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda-functions/${each.key}-check/${each.key}.zip")

  runtime     = "python3.12"
  handler     = "handler.handler"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_mb

  # VPC config — keeps Lambda inside private subnets
  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"    # X-Ray active tracing
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      LOG_LEVEL    = "INFO"
      AWS_XRAY_SDK_ENABLED = "true"
    }
  }

  reserved_concurrent_executions = 50

  tags = {
    check = each.key
  }
}

# Lambda function URL for each check — optional, direct HTTPS invocations
# resource "aws_lambda_function_url" "check_url" { ... }

# ── Lambda aliases :live ──────────────────────────────────────────────────────
resource "aws_lambda_alias" "live" {
  for_each = toset(local.lambda_checks)

  name             = "live"
  description      = "Current live version"
  function_name    = aws_lambda_function.compliance_checks[each.key].function_name
  function_version = "$LATEST"
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset(local.lambda_checks)

  name              = "/aws/lambda/${var.project}-${each.key}"
  retention_in_days = 30

  tags = {
    lambda = "${var.project}-${each.key}"
  }
}

# ── Security Group for Lambda VPC ────────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "${var.project}-lambda-sg"
  description = "SG for compliance check Lambda functions"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-lambda-sg" }
}

# ── ECR Repository ────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "compliance_scanner" {
  name                 = "${var.project}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true    # Trivy/ECR scan on every push
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "compliance_scanner" {
  repository = aws_ecr_repository.compliance_scanner.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["stable", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
