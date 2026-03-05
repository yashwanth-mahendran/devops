# AWS Step Functions - Deep Dive Guide

Complete guide to workflow orchestration with AWS Step Functions.

---

## Table of Contents

1. [Step Functions Overview](#step-functions-overview)
2. [State Types](#state-types)
3. [Workflow Patterns](#workflow-patterns)
4. [Error Handling](#error-handling)
5. [Express vs Standard Workflows](#express-vs-standard-workflows)
6. [Integration Patterns](#integration-patterns)
7. [Best Practices](#best-practices)
8. [Interview Questions](#interview-questions)

---

## Step Functions Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            STEP FUNCTIONS                                        │
│                                                                                  │
│  ┌──────────────┐     ┌──────────────────────────────────────────────────────┐ │
│  │   TRIGGER    │     │                  STATE MACHINE                       │ │
│  │              │     │                                                      │ │
│  │ • API Gateway│────▶│  Start → Task1 → Choice → Task2 → Parallel → End   │ │
│  │ • EventBridge│     │                    │                  │              │ │
│  │ • Lambda     │     │                    ▼                  ▼              │ │
│  │ • S3         │     │                 Task3              Task4a            │ │
│  │ • SQS        │     │                                    Task4b            │ │
│  │ • SDK        │     │                                    Task4c            │ │
│  └──────────────┘     └──────────────────────────────────────────────────────┘ │
│                                                                                  │
│                        ┌──────────────────────────────────────┐                 │
│                        │           INTEGRATIONS               │                 │
│                        │                                      │                 │
│                        │  Lambda | ECS | SNS | SQS | DynamoDB │                 │
│                        │  Batch | Glue | SageMaker | EMR      │                 │
│                        │  CodeBuild | API Gateway | HTTP      │                 │
│                        └──────────────────────────────────────┘                 │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Step Functions vs Alternatives

| Feature | Step Functions | SQS + Lambda | EventBridge |
|---------|---------------|--------------|-------------|
| **Orchestration** | Yes (visual) | No | Event routing |
| **State Management** | Built-in | Manual | No |
| **Error Handling** | Rich (retry, catch) | Manual | Limited |
| **Long Running** | Up to 1 year | Limited | Event-based |
| **Cost** | Per transition | Per message | Per event |
| **Visibility** | Execution history | Limited | Event logs |
| **Best For** | Complex workflows | Simple queues | Event routing |

---

## State Types

### Complete State Reference

| State Type | Purpose | Example Use |
|------------|---------|-------------|
| **Task** | Execute work | Invoke Lambda, ECS task |
| **Choice** | Branch logic | If/else conditions |
| **Parallel** | Concurrent execution | Run multiple branches |
| **Map** | Iterate over array | Process multiple items |
| **Wait** | Pause execution | Wait for time/timestamp |
| **Pass** | Transform data | Inject/modify state |
| **Succeed** | Mark success | Terminal state |
| **Fail** | Mark failure | Terminal state |

### Task State

```json
{
  "ProcessOrder": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:us-east-1:123456789012:function:ProcessOrder",
    "InputPath": "$.order",
    "ResultPath": "$.orderResult",
    "OutputPath": "$",
    "TimeoutSeconds": 300,
    "HeartbeatSeconds": 60,
    "Retry": [
      {
        "ErrorEquals": ["States.Timeout", "Lambda.ServiceException"],
        "IntervalSeconds": 3,
        "MaxAttempts": 3,
        "BackoffRate": 2
      }
    ],
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }
    ],
    "Next": "Notify"
  }
}
```

### Choice State

```json
{
  "CheckOrderStatus": {
    "Type": "Choice",
    "Choices": [
      {
        "Variable": "$.orderResult.status",
        "StringEquals": "APPROVED",
        "Next": "ProcessPayment"
      },
      {
        "Variable": "$.orderResult.status",
        "StringEquals": "PENDING_REVIEW",
        "Next": "ManualReview"
      },
      {
        "Variable": "$.orderResult.amount",
        "NumericGreaterThan": 10000,
        "Next": "HighValueProcess"
      },
      {
        "And": [
          {
            "Variable": "$.orderResult.isPrime",
            "BooleanEquals": true
          },
          {
            "Variable": "$.orderResult.amount",
            "NumericGreaterThan": 100
          }
        ],
        "Next": "PrimeProcessing"
      }
    ],
    "Default": "StandardProcess"
  }
}
```

### Parallel State

```json
{
  "ProcessInParallel": {
    "Type": "Parallel",
    "Branches": [
      {
        "StartAt": "UpdateInventory",
        "States": {
          "UpdateInventory": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:UpdateInventory",
            "End": true
          }
        }
      },
      {
        "StartAt": "SendNotification",
        "States": {
          "SendNotification": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:SendNotification",
            "End": true
          }
        }
      },
      {
        "StartAt": "UpdateAnalytics",
        "States": {
          "UpdateAnalytics": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:UpdateAnalytics",
            "End": true
          }
        }
      }
    ],
    "ResultPath": "$.parallelResults",
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleParallelError"
      }
    ],
    "Next": "FinalizeOrder"
  }
}
```

### Map State (Inline)

```json
{
  "ProcessItems": {
    "Type": "Map",
    "ItemsPath": "$.items",
    "MaxConcurrency": 10,
    "ItemProcessor": {
      "ProcessorConfig": {
        "Mode": "INLINE"
      },
      "StartAt": "ProcessItem",
      "States": {
        "ProcessItem": {
          "Type": "Task",
          "Resource": "arn:aws:lambda:...:ProcessItem",
          "End": true
        }
      }
    },
    "ResultPath": "$.processedItems",
    "Next": "Consolidate"
  }
}
```

### Map State (Distributed - for large datasets)

```json
{
  "ProcessLargeDataset": {
    "Type": "Map",
    "ItemReader": {
      "Resource": "arn:aws:states:::s3:getObject",
      "ReaderConfig": {
        "InputType": "JSON"
      },
      "Parameters": {
        "Bucket": "my-bucket",
        "Key": "data.json"
      }
    },
    "ItemProcessor": {
      "ProcessorConfig": {
        "Mode": "DISTRIBUTED",
        "ExecutionType": "STANDARD"
      },
      "StartAt": "ProcessBatch",
      "States": {
        "ProcessBatch": {
          "Type": "Task",
          "Resource": "arn:aws:lambda:...:ProcessBatch",
          "End": true
        }
      }
    },
    "ItemBatcher": {
      "MaxItemsPerBatch": 100
    },
    "ResultWriter": {
      "Resource": "arn:aws:states:::s3:putObject",
      "Parameters": {
        "Bucket": "my-bucket",
        "Prefix": "results/"
      }
    },
    "MaxConcurrency": 1000,
    "Next": "Done"
  }
}
```

---

## Workflow Patterns

### Order Processing Workflow

```json
{
  "Comment": "Order Processing Workflow",
  "StartAt": "ValidateOrder",
  "States": {
    "ValidateOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:ValidateOrder",
      "ResultPath": "$.validation",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["ValidationError"],
          "ResultPath": "$.error",
          "Next": "NotifyValidationFailure"
        }
      ],
      "Next": "CheckOrderAmount"
    },

    "CheckOrderAmount": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.order.amount",
          "NumericGreaterThan": 1000,
          "Next": "HighValueOrderProcess"
        }
      ],
      "Default": "StandardProcess"
    },

    "HighValueOrderProcess": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "FraudCheck",
          "States": {
            "FraudCheck": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:...:FraudCheck",
              "End": true
            }
          }
        },
        {
          "StartAt": "CreditCheck",
          "States": {
            "CreditCheck": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:...:CreditCheck",
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.checks",
      "Next": "EvaluateChecks"
    },

    "EvaluateChecks": {
      "Type": "Choice",
      "Choices": [
        {
          "And": [
            {
              "Variable": "$.checks[0].passed",
              "BooleanEquals": true
            },
            {
              "Variable": "$.checks[1].passed",
              "BooleanEquals": true
            }
          ],
          "Next": "ProcessPayment"
        }
      ],
      "Default": "ManualReview"
    },

    "StandardProcess": {
      "Type": "Pass",
      "Next": "ProcessPayment"
    },

    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "Parameters": {
        "QueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789012/payments",
        "MessageBody": {
          "orderId.$": "$.order.id",
          "amount.$": "$.order.amount",
          "taskToken.$": "$$.Task.Token"
        }
      },
      "TimeoutSeconds": 3600,
      "Next": "FulfillOrder"
    },

    "FulfillOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "arn:aws:ecs:...:cluster/fulfillment",
        "TaskDefinition": "arn:aws:ecs:...:task-definition/fulfillment:1",
        "Overrides": {
          "ContainerOverrides": [
            {
              "Name": "fulfillment",
              "Environment": [
                {
                  "Name": "ORDER_ID",
                  "Value.$": "$.order.id"
                }
              ]
            }
          ]
        }
      },
      "Next": "NotifySuccess"
    },

    "ManualReview": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish.waitForTaskToken",
      "Parameters": {
        "TopicArn": "arn:aws:sns:...:manual-review",
        "Message": {
          "orderId.$": "$.order.id",
          "taskToken.$": "$$.Task.Token"
        }
      },
      "TimeoutSeconds": 86400,
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "Next": "NotifyTimeout"
        }
      ],
      "Next": "ProcessPayment"
    },

    "NotifySuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:...:order-notifications",
        "Subject": "Order Completed",
        "Message.$": "States.Format('Order {} has been processed', $.order.id)"
      },
      "End": true
    },

    "NotifyValidationFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:...:order-failures",
        "Message.$": "$.error"
      },
      "Next": "FailState"
    },

    "NotifyTimeout": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:...:order-timeouts",
        "Message": "Manual review timed out"
      },
      "Next": "FailState"
    },

    "FailState": {
      "Type": "Fail",
      "Error": "OrderProcessingFailed",
      "Cause": "Order could not be processed"
    }
  }
}
```

### Human Approval Workflow

```json
{
  "Comment": "Human Approval Workflow using Callback Pattern",
  "StartAt": "SubmitRequest",
  "States": {
    "SubmitRequest": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:SubmitRequest",
      "ResultPath": "$.request",
      "Next": "SendApprovalRequest"
    },

    "SendApprovalRequest": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish.waitForTaskToken",
      "Parameters": {
        "TopicArn": "arn:aws:sns:...:approvals",
        "Message": {
          "requestId.$": "$.request.id",
          "details.$": "$.request.details",
          "approvalUrl.$": "States.Format('https://approve.example.com?token={}', $$.Task.Token)",
          "rejectUrl.$": "States.Format('https://reject.example.com?token={}', $$.Task.Token)",
          "taskToken.$": "$$.Task.Token"
        }
      },
      "ResultPath": "$.approval",
      "TimeoutSeconds": 604800,
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "ResultPath": "$.error",
          "Next": "ApprovalTimedOut"
        }
      ],
      "Next": "CheckApprovalResult"
    },

    "CheckApprovalResult": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.approval.status",
          "StringEquals": "APPROVED",
          "Next": "ProcessApprovedRequest"
        }
      ],
      "Default": "ProcessRejectedRequest"
    },

    "ProcessApprovedRequest": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:ProcessApproved",
      "End": true
    },

    "ProcessRejectedRequest": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:ProcessRejected",
      "End": true
    },

    "ApprovalTimedOut": {
      "Type": "Fail",
      "Error": "ApprovalTimeout",
      "Cause": "Approval request timed out after 7 days"
    }
  }
}
```

---

## Error Handling

### Retry Configuration

```json
{
  "States": {
    "CallExternalAPI": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:CallAPI",
      "Retry": [
        {
          "ErrorEquals": ["States.Timeout"],
          "IntervalSeconds": 3,
          "MaxAttempts": 2,
          "BackoffRate": 1
        },
        {
          "ErrorEquals": ["RateLimitExceeded"],
          "IntervalSeconds": 10,
          "MaxAttempts": 5,
          "BackoffRate": 2,
          "JitterStrategy": "FULL"
        },
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        },
        {
          "ErrorEquals": ["States.ALL"],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleAPIError"
        }
      ],
      "Next": "Success"
    }
  }
}
```

### Error Types

| Error | Cause | Handling |
|-------|-------|----------|
| `States.Timeout` | Task exceeded TimeoutSeconds | Retry or Catch |
| `States.TaskFailed` | Task returned error | Retry or Catch |
| `States.Permissions` | IAM permission denied | Fix permissions |
| `States.ResultPathMatchFailure` | ResultPath doesn't fit | Fix state definition |
| `Lambda.ServiceException` | Lambda service error | Retry |
| `Lambda.AWSLambdaException` | Lambda SDK error | Retry |
| `Lambda.SdkClientException` | SDK issue | Retry |
| Custom errors | Thrown by your code | Handle specifically |

---

## Express vs Standard Workflows

### Comparison

| Feature | Standard | Express |
|---------|----------|---------|
| **Duration** | Up to 1 year | Up to 5 minutes |
| **Pricing** | Per state transition | Per invocation + duration |
| **Execution History** | 90 days | CloudWatch Logs only |
| **Start Rate** | 2,000/sec | 100,000/sec |
| **Exactly-once** | Yes | At-least-once |
| **Use Case** | Long-running, auditable | High-volume, short |

### Terraform Configuration

```hcl
# Standard Workflow
resource "aws_sfn_state_machine" "standard" {
  name       = "order-processing"
  role_arn   = aws_iam_role.step_functions.arn
  definition = file("${path.module}/order-workflow.json")
  type       = "STANDARD"
  
  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
  }
  
  tracing_configuration {
    enabled = true
  }
  
  tags = {
    Environment = var.environment
  }
}

# Express Workflow
resource "aws_sfn_state_machine" "express" {
  name       = "api-processor"
  role_arn   = aws_iam_role.step_functions.arn
  definition = file("${path.module}/api-workflow.json")
  type       = "EXPRESS"
  
  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.sfn_express.arn}:*"
  }
}

# IAM Role
resource "aws_iam_role" "step_functions" {
  name = "step-functions-role"
  
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
}

resource "aws_iam_role_policy" "step_functions" {
  name = "step-functions-policy"
  role = aws_iam_role.step_functions.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = "*"
      },
      {
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
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}
```

---

## Integration Patterns

### AWS SDK Integrations

```json
{
  "DynamoDBPutItem": {
    "Type": "Task",
    "Resource": "arn:aws:states:::dynamodb:putItem",
    "Parameters": {
      "TableName": "Orders",
      "Item": {
        "orderId": {"S.$": "$.order.id"},
        "status": {"S": "PROCESSING"},
        "amount": {"N.$": "States.Format('{}', $.order.amount)"}
      }
    },
    "ResultPath": "$.dynamoResult",
    "Next": "NextState"
  },

  "S3GetObject": {
    "Type": "Task",
    "Resource": "arn:aws:states:::aws-sdk:s3:getObject",
    "Parameters": {
      "Bucket": "my-bucket",
      "Key.$": "$.s3Key"
    },
    "ResultSelector": {
      "content.$": "States.StringToJson($.Body)"
    },
    "Next": "ProcessContent"
  },

  "SQSSendMessage": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage",
    "Parameters": {
      "QueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789012/my-queue",
      "MessageBody.$": "States.JsonToString($.message)",
      "MessageGroupId.$": "$.orderId"
    },
    "Next": "NextState"
  },

  "ECSRunTask": {
    "Type": "Task",
    "Resource": "arn:aws:states:::ecs:runTask.sync",
    "Parameters": {
      "LaunchType": "FARGATE",
      "Cluster": "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster",
      "TaskDefinition": "arn:aws:ecs:us-east-1:123456789012:task-definition/my-task:1",
      "NetworkConfiguration": {
        "AwsvpcConfiguration": {
          "Subnets": ["subnet-12345678"],
          "SecurityGroups": ["sg-12345678"],
          "AssignPublicIp": "DISABLED"
        }
      },
      "Overrides": {
        "ContainerOverrides": [{
          "Name": "my-container",
          "Environment": [{
            "Name": "INPUT_DATA",
            "Value.$": "States.JsonToString($.data)"
          }]
        }]
      }
    },
    "Next": "Done"
  },

  "HTTPEndpoint": {
    "Type": "Task",
    "Resource": "arn:aws:states:::http:invoke",
    "Parameters": {
      "ApiEndpoint": "https://api.example.com/process",
      "Method": "POST",
      "Headers": {
        "Content-Type": "application/json",
        "Authorization.$": "States.Format('Bearer {}', $.token)"
      },
      "RequestBody.$": "$.payload"
    },
    "Retry": [{
      "ErrorEquals": ["States.Http.StatusCode.429"],
      "IntervalSeconds": 10,
      "MaxAttempts": 3,
      "BackoffRate": 2
    }],
    "Next": "ProcessResponse"
  }
}
```

### Callback Pattern (Wait for External Task)

```json
{
  "WaitForPayment": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
    "Parameters": {
      "QueueUrl": "https://sqs.../payment-queue",
      "MessageBody": {
        "orderId.$": "$.order.id",
        "amount.$": "$.order.amount",
        "taskToken.$": "$$.Task.Token"
      }
    },
    "TimeoutSeconds": 86400,
    "HeartbeatSeconds": 300,
    "Next": "ProcessPaymentResult"
  }
}
```

```python
# External service sends callback
import boto3

sfn = boto3.client('stepfunctions')

def payment_processed(task_token, result):
    sfn.send_task_success(
        taskToken=task_token,
        output=json.dumps(result)
    )

def payment_failed(task_token, error):
    sfn.send_task_failure(
        taskToken=task_token,
        error='PaymentFailed',
        cause=str(error)
    )
```

---

## Best Practices

### Design Guidelines

| Category | Best Practice |
|----------|---------------|
| **State Machine** | Keep state machines focused, not too large |
| **Error Handling** | Always have Catch blocks for States.ALL |
| **Timeouts** | Set appropriate TimeoutSeconds on all Tasks |
| **Idempotency** | Design tasks to be idempotent |
| **Data** | Use InputPath/OutputPath/ResultPath to limit data |
| **Logging** | Enable logging for production workflows |
| **Testing** | Test individual states before full workflow |

### Payload Management

```json
{
  "Comment": "Use filters to manage payload size",
  "States": {
    "GetOrderDetails": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:GetOrder",
      "InputPath": "$.orderId",
      "ResultSelector": {
        "id.$": "$.id",
        "items.$": "$.items",
        "total.$": "$.total"
      },
      "ResultPath": "$.orderDetails",
      "Next": "ProcessOrder"
    }
  }
}
```

---

## Interview Questions

### Q1: When would you use Step Functions over SQS + Lambda?

**Answer:**

**Use Step Functions when:**
- Complex workflows with branching/parallel logic
- Need visual representation and debugging
- Require long-running processes (up to 1 year)
- Need built-in retry and error handling
- Want execution history and audit trail
- Human approval workflows

**Use SQS + Lambda when:**
- Simple message processing
- High throughput, simple queuing
- Decoupling services with async messaging
- Dead letter queue handling
- Lower cost for simple patterns

---

### Q2: Explain the callback pattern in Step Functions.

**Answer:**

**Callback Pattern:**
1. Step Functions pauses and provides a task token
2. External system receives token with message
3. External system processes work asynchronously
4. External system calls `SendTaskSuccess` or `SendTaskFailure` with token
5. Step Functions resumes execution

```
State Machine                 External System
     │                              │
     │─── Task + Token ────────────▶│
     │    (Paused)                  │
     │                              │ Process
     │                              │ work
     │◀── SendTaskSuccess(token) ───│
     │    (Resumed)                 │
     ▼                              │
```

**Use cases:**
- Human approvals
- Payment processing
- External service integration
- Long-running batch jobs

---

### Q3: How would you handle a workflow that needs to process 1 million items?

**Answer:**

**Use Distributed Map:**

```json
{
  "ProcessMillionItems": {
    "Type": "Map",
    "ItemReader": {
      "Resource": "arn:aws:states:::s3:getObject",
      "Parameters": {
        "Bucket": "data-bucket",
        "Key": "million-items.json"
      }
    },
    "ItemProcessor": {
      "ProcessorConfig": {
        "Mode": "DISTRIBUTED",
        "ExecutionType": "EXPRESS"
      },
      "StartAt": "ProcessItem",
      "States": {
        "ProcessItem": {
          "Type": "Task",
          "Resource": "arn:aws:lambda:...:ProcessItem",
          "End": true
        }
      }
    },
    "ItemBatcher": {
      "MaxItemsPerBatch": 100
    },
    "MaxConcurrency": 1000,
    "ResultWriter": {
      "Resource": "arn:aws:states:::s3:putObject",
      "Parameters": {
        "Bucket": "results-bucket",
        "Prefix": "results/"
      }
    }
  }
}
```

**Benefits:**
- Handles millions of items
- Up to 10,000 concurrent child executions
- Automatic batching and result aggregation
- Cost-effective with Express workflows
