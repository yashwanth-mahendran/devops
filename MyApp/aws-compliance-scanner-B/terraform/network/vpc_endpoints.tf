################################################################################
# Gateway Endpoints (S3, DynamoDB) - No Cost
################################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id]
  )

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id]
  )

  tags = {
    Name = "${var.project_name}-dynamodb-endpoint"
  }
}

################################################################################
# Interface Endpoints (PrivateLink)
################################################################################

locals {
  vpc_endpoints = {
    "states"         = "com.amazonaws.${var.aws_region}.states"          # Step Functions
    "lambda"         = "com.amazonaws.${var.aws_region}.lambda"          # Lambda
    "sts"            = "com.amazonaws.${var.aws_region}.sts"             # STS (for IRSA)
    "secretsmanager" = "com.amazonaws.${var.aws_region}.secretsmanager"  # Secrets
    "logs"           = "com.amazonaws.${var.aws_region}.logs"            # CloudWatch Logs
    "ecr-api"        = "com.amazonaws.${var.aws_region}.ecr.api"         # ECR API
    "ecr-dkr"        = "com.amazonaws.${var.aws_region}.ecr.dkr"         # ECR Docker
    "xray"           = "com.amazonaws.${var.aws_region}.xray"            # X-Ray
    "ssm"            = "com.amazonaws.${var.aws_region}.ssm"             # Systems Manager
    "kms"            = "com.amazonaws.${var.aws_region}.kms"             # KMS
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.vpc_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.isolated[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${each.key}-endpoint"
  }
}

################################################################################
# VPC Endpoint Policy for Step Functions (Restrict to our state machine)
################################################################################

resource "aws_vpc_endpoint_policy" "stepfunctions" {
  vpc_endpoint_id = aws_vpc_endpoint.interface["states"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOurStateMachine"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "states:StartExecution",
          "states:StartSyncExecution",
          "states:StopExecution",
          "states:DescribeExecution",
          "states:GetExecutionHistory"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

################################################################################
# VPC Endpoint Policy for Lambda
################################################################################

resource "aws_vpc_endpoint_policy" "lambda" {
  vpc_endpoint_id = aws_vpc_endpoint.interface["lambda"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOurLambdas"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "lambda:InvokeFunction",
          "lambda:InvokeAsync"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
