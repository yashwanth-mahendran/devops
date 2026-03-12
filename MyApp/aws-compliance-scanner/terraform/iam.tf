# ── IAM Role for Lambda functions (Compliance Checks) ───────────────────────

resource "aws_iam_role" "lambda_compliance" {
  name = "${var.project}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_compliance_policy" {
  name = "${var.project}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── CloudWatch Logs ─────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project}-*"
      },
      # ── X-Ray tracing ───────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      # ── STS AssumeRole — for cross-account scanning ─────────────────────
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/ComplianceScannerRole"
      },
      # ── CloudFormation drift detection ──────────────────────────────────
      {
        Effect   = "Allow"
        Action   = [
          "cloudformation:DescribeStacks",
          "cloudformation:DetectStackDrift",
          "cloudformation:DescribeStackDriftDetectionStatus",
          "cloudformation:ListStacks",
        ]
        Resource = "*"
      },
      # ── EC2 (VPC flow logs, security groups) ────────────────────────────
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeVpcs",
          "ec2:DescribeFlowLogs",
          "ec2:DescribeSecurityGroups",
        ]
        Resource = "*"
      },
      # ── IAM ─────────────────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = [
          "iam:GetAccountSummary",
          "iam:ListUsers",
          "iam:ListMFADevices",
          "iam:GetLoginProfile",
        ]
        Resource = "*"
      },
      # ── S3 ──────────────────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetEncryptionConfiguration"]
        Resource = "*"
      },
      # ── CloudTrail ──────────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["cloudtrail:DescribeTrails", "cloudtrail:GetTrailStatus"]
        Resource = "*"
      },
      # ── GuardDuty ───────────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["guardduty:ListDetectors", "guardduty:GetDetector"]
        Resource = "*"
      },
      # ── Audit Manager ───────────────────────────────────────────────────
      {
        Effect   = "Allow"
        Action   = ["auditmanager:GetSettings", "auditmanager:ListAssessments"]
        Resource = "*"
      },
      # ── Lambda VPC + ENI (if running inside VPC) ─────────────────────────
      {
        Effect   = "Allow"
        Action   = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_compliance" {
  role       = aws_iam_role.lambda_compliance.name
  policy_arn = aws_iam_policy.lambda_compliance_policy.arn
}


# ── IRSA Role for FastAPI on EKS ─────────────────────────────────────────────

module "irsa_compliance_scanner" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.project}-irsa-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["compliance:compliance-scanner"]
    }
  }

  role_policy_arns = {
    dynamodb = aws_iam_policy.fastapi_dynamodb_policy.arn
    lambda   = aws_iam_policy.fastapi_lambda_invoke_policy.arn
  }
}

resource "aws_iam_policy" "fastapi_dynamodb_policy" {
  name = "${var.project}-fastapi-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:PutItem", "dynamodb:GetItem",
        "dynamodb:UpdateItem", "dynamodb:Query",
        "dynamodb:Scan", "dynamodb:DeleteItem",
      ]
      Resource = [
        aws_dynamodb_table.scan_results.arn,
        aws_dynamodb_table.scan_jobs.arn,
        "${aws_dynamodb_table.scan_results.arn}/index/*",
        "${aws_dynamodb_table.scan_jobs.arn}/index/*",
      ]
    }]
  })
}

resource "aws_iam_policy" "fastapi_lambda_invoke_policy" {
  name = "${var.project}-fastapi-lambda-invoke"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = "arn:aws:lambda:${var.aws_region}:*:function:${var.project}-*"
    }]
  })
}


# ── Cross-Account ComplianceScannerRole (deploy to each target account) ──────
# This is a TEMPLATE of what gets deployed to each customer account.

resource "aws_iam_role" "compliance_scanner_target" {
  count = 0   # set to 1 to create in the current account for testing
  name  = "ComplianceScannerRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-lambda-role"
      }
      Action = "sts:AssumeRole"
    }]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/SecurityAudit", "arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

data "aws_caller_identity" "current" {}
