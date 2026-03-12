# ─────────────────────────────────────────────────────────────────────────────
# STEP FUNCTIONS — Compliance Scan Orchestrator
# ─────────────────────────────────────────────────────────────────────────────
# This state machine orchestrates compliance checks by:
# 1. Receiving scan parameters from FastAPI
# 2. Dynamically choosing which Lambda functions to invoke based on check IDs
# 3. Running checks in parallel using Map state (per account/region/check)
# 4. Aggregating results and writing to DynamoDB
# ─────────────────────────────────────────────────────────────────────────────

# IAM Role for Step Functions
resource "aws_iam_role" "stepfunctions_compliance" {
  name = "${var.project}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-sfn-role" }
}

# IAM Policy: Invoke Lambda + DynamoDB + CloudWatch Logs
resource "aws_iam_role_policy" "stepfunctions_compliance" {
  name = "${var.project}-sfn-policy"
  role = aws_iam_role.stepfunctions_compliance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project}-*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project}-*:*"
        ]
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.scan_jobs.arn,
          aws_dynamodb_table.scan_results.arn
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "stepfunctions" {
  name              = "/aws/vendedlogs/states/${var.project}-compliance-scanner"
  retention_in_days = 30

  tags = { Name = "${var.project}-sfn-logs" }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP FUNCTION STATE MACHINE — Express Workflow
# ─────────────────────────────────────────────────────────────────────────────
# Uses EXPRESS type for:
# - Higher throughput (100,000 executions/sec)
# - Lower latency (sub-second start)
# - Cost-effective for short-duration workloads
# - Synchronous execution support (ideal for API-driven use cases)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sfn_state_machine" "compliance_scanner" {
  name     = "${var.project}-orchestrator"
  role_arn = aws_iam_role.stepfunctions_compliance.arn
  type     = "EXPRESS"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  definition = jsonencode({
    Comment = "AWS Compliance Scanner Orchestrator - Routes to appropriate Lambda functions based on check type"
    StartAt = "PrepareCheckTasks"

    States = {
      # ─────────────────────────────────────────────────────────────────────
      # Step 1: Update job status to RUNNING
      # ─────────────────────────────────────────────────────────────────────
      PrepareCheckTasks = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.scan_jobs.name
          Key = {
            job_id = { "S.$" = "$.job_id" }
          }
          UpdateExpression = "SET #status = :status, started_at = :started_at"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status"     = { S = "RUNNING" }
            ":started_at" = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        ResultPath = "$.dynamodb_update"
        Next       = "BuildCheckMatrix"
      }

      # ─────────────────────────────────────────────────────────────────────
      # Step 2: Build the check matrix (account × region × check)
      # ─────────────────────────────────────────────────────────────────────
      BuildCheckMatrix = {
        Type = "Pass"
        Parameters = {
          "job_id.$"       = "$.job_id"
          "account_ids.$"  = "$.account_ids"
          "regions.$"      = "$.regions"
          "checks.$"       = "$.checks"
          "trace_context.$"= "$.trace_context"
        }
        Next = "FanOutByAccount"
      }

      # ─────────────────────────────────────────────────────────────────────
      # Step 3: Fan out by account (outer Map)
      # ─────────────────────────────────────────────────────────────────────
      FanOutByAccount = {
        Type       = "Map"
        ItemsPath  = "$.account_ids"
        MaxConcurrency = 10
        Parameters = {
          "job_id.$"        = "$.job_id"
          "account_id.$"    = "$$.Map.Item.Value"
          "regions.$"       = "$.regions"
          "checks.$"        = "$.checks"
          "trace_context.$" = "$.trace_context"
        }
        Iterator = {
          StartAt = "FanOutByRegion"
          States = {
            FanOutByRegion = {
              Type       = "Map"
              ItemsPath  = "$.regions"
              MaxConcurrency = 5
              Parameters = {
                "job_id.$"        = "$.job_id"
                "account_id.$"    = "$.account_id"
                "region.$"        = "$$.Map.Item.Value"
                "checks.$"        = "$.checks"
                "trace_context.$" = "$.trace_context"
              }
              Iterator = {
                StartAt = "FanOutByCheck"
                States = {
                  FanOutByCheck = {
                    Type       = "Map"
                    ItemsPath  = "$.checks"
                    MaxConcurrency = 15
                    Parameters = {
                      "job_id.$"        = "$.job_id"
                      "account_id.$"    = "$.account_id"
                      "region.$"        = "$.region"
                      "check_id.$"      = "$$.Map.Item.Value"
                      "trace_context.$" = "$.trace_context"
                    }
                    Iterator = {
                      StartAt = "RouteToCheck"
                      States = {
                        # ─────────────────────────────────────────────────────
                        # CHOICE STATE: Route to appropriate Lambda based on check_id
                        # ─────────────────────────────────────────────────────
                        RouteToCheck = {
                          Type    = "Choice"
                          Choices = [
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "cfn_drift"
                              Next          = "InvokeCfnDriftCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "vpc_flow_logs"
                              Next          = "InvokeVpcFlowLogsCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "s3_encryption"
                              Next          = "InvokeS3EncryptionCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "iam_mfa_root"
                              Next          = "InvokeIamMfaCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "iam_mfa_users"
                              Next          = "InvokeIamMfaCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "cloudtrail_enabled"
                              Next          = "InvokeCloudtrailCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "sg_unrestricted_ssh"
                              Next          = "InvokeSgUnrestrictedSshCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "guardduty_enabled"
                              Next          = "InvokeGuarddutyCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "config_recorder"
                              Next          = "InvokeConfigRecorderCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "audit_manager_enabled"
                              Next          = "InvokeAuditManagerCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "rds_encryption"
                              Next          = "InvokeRdsEncryptionCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "ebs_encryption"
                              Next          = "InvokeEbsEncryptionCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "secrets_manager_rotation"
                              Next          = "InvokeSecretsManagerCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "ecr_image_scanning"
                              Next          = "InvokeEcrScanningCheck"
                            },
                            {
                              Variable      = "$.check_id"
                              StringEquals  = "eks_cluster_logging"
                              Next          = "InvokeEksLoggingCheck"
                            }
                          ]
                          Default = "UnknownCheckHandler"
                        }

                        # ─────────────────────────────────────────────────────
                        # Lambda Invocation States (one per check type)
                        # ─────────────────────────────────────────────────────
                        InvokeCfnDriftCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-cfn-drift:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeVpcFlowLogsCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-vpc-flow-logs:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next       = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeS3EncryptionCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-s3-encryption:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeIamMfaCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-iam-mfa:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeCloudtrailCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-cloudtrail:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeSgUnrestrictedSshCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-sg-unrestricted-ssh:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeGuarddutyCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-guardduty:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeConfigRecorderCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-config-recorder:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeAuditManagerCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-audit-manager:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeRdsEncryptionCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-rds-encryption:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeEbsEncryptionCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-ebs-encryption:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeSecretsManagerCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-secrets-manager-rotation:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeEcrScanningCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-ecr-image-scanning:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        InvokeEksLoggingCheck = {
                          Type     = "Task"
                          Resource = "arn:aws:states:::lambda:invoke"
                          Parameters = {
                            FunctionName = "${var.project}-eks-cluster-logging:live"
                            "Payload.$"  = "$"
                          }
                          ResultSelector = {
                            "check_id.$"    = "$.Payload.check_id"
                            "status.$"      = "$.Payload.status"
                            "message.$"     = "$.Payload.message"
                            "resource_id.$" = "$.Payload.resource_id"
                            "remediation.$" = "$.Payload.remediation"
                            "account_id.$"  = "$.Payload.account_id"
                            "region.$"      = "$.Payload.region"
                          }
                          Retry = [{
                            ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
                            IntervalSeconds = 2
                            MaxAttempts     = 3
                            BackoffRate     = 2.0
                          }]
                          Catch = [{
                            ErrorEquals = ["States.ALL"]
                            ResultPath  = "$.error"
                            Next        = "HandleCheckError"
                          }]
                          End = true
                        }

                        # Unknown check handler
                        UnknownCheckHandler = {
                          Type   = "Pass"
                          Result = {
                            status      = "ERROR"
                            message     = "Unknown check type"
                            remediation = "Verify check_id is valid"
                          }
                          ResultPath = "$.result"
                          End        = true
                        }

                        # Error handler for failed checks
                        HandleCheckError = {
                          Type = "Pass"
                          Parameters = {
                            "check_id.$"   = "$.check_id"
                            "account_id.$" = "$.account_id"
                            "region.$"     = "$.region"
                            status         = "ERROR"
                            "message.$"    = "$.error.Error"
                            "cause.$"      = "$.error.Cause"
                          }
                          End = true
                        }
                      }
                    }
                    ResultPath = "$.check_results"
                    End        = true
                  }
                }
              }
              ResultPath = "$.region_results"
              End        = true
            }
          }
        }
        ResultPath = "$.account_results"
        Next       = "AggregateResults"
      }

      # ─────────────────────────────────────────────────────────────────────
      # Step 4: Aggregate results and update job status
      # ─────────────────────────────────────────────────────────────────────
      AggregateResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = "${var.project}-result-aggregator:live"
          Payload = {
            "job_id.$"         = "$.job_id"
            "account_results.$"= "$.account_results"
          }
        }
        ResultPath = "$.aggregation"
        Next       = "UpdateJobComplete"
      }

      # ─────────────────────────────────────────────────────────────────────
      # Step 5: Mark job as completed in DynamoDB
      # ─────────────────────────────────────────────────────────────────────
      UpdateJobComplete = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.scan_jobs.name
          Key = {
            job_id = { "S.$" = "$.job_id" }
          }
          UpdateExpression = "SET #status = :status, completed_at = :completed_at, passed = :passed, failed = :failed, errors = :errors, total_checks = :total"
          ExpressionAttributeNames = {
            "#status" = "status"
          }
          ExpressionAttributeValues = {
            ":status"       = { S = "COMPLETED" }
            ":completed_at" = { "S.$" = "$$.State.EnteredTime" }
            ":passed"       = { "N.$" = "States.Format('{}', $.aggregation.Payload.passed)" }
            ":failed"       = { "N.$" = "States.Format('{}', $.aggregation.Payload.failed)" }
            ":errors"       = { "N.$" = "States.Format('{}', $.aggregation.Payload.errors)" }
            ":total"        = { "N.$" = "States.Format('{}', $.aggregation.Payload.total)" }
          }
        }
        End = true
      }
    }
  })

  tags = { Name = "${var.project}-sfn" }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESULT AGGREGATOR LAMBDA
# ─────────────────────────────────────────────────────────────────────────────
# Flattens nested Map results and writes to DynamoDB
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "result_aggregator" {
  function_name = "${var.project}-result-aggregator"
  description   = "Aggregates compliance check results from Step Functions Map state"
  role          = aws_iam_role.lambda_compliance.arn

  filename         = "${path.module}/../lambda-functions/result-aggregator/result-aggregator.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda-functions/result-aggregator/result-aggregator.zip")

  runtime     = "python3.12"
  handler     = "handler.handler"
  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      DYNAMODB_RESULTS_TABLE = aws_dynamodb_table.scan_results.name
      ENVIRONMENT            = var.environment
    }
  }

  tags = { Name = "${var.project}-result-aggregator" }
}

resource "aws_lambda_alias" "result_aggregator_live" {
  name             = "live"
  description      = "Live alias for result aggregator"
  function_name    = aws_lambda_function.result_aggregator.function_name
  function_version = "$LATEST"
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "stepfunctions_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.compliance_scanner.arn
}

output "stepfunctions_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.compliance_scanner.name
}
