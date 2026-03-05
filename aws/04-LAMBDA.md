# AWS Lambda - Deep Dive Guide

Complete guide to Lambda architecture, patterns, optimization, and troubleshooting.

---

## Table of Contents

1. [Lambda Architecture](#lambda-architecture)
2. [Function Configuration](#function-configuration)
3. [Triggers and Integrations](#triggers-and-integrations)
4. [Cold Starts and Performance](#cold-starts-and-performance)
5. [Concurrency and Scaling](#concurrency-and-scaling)
6. [Error Handling and Retries](#error-handling-and-retries)
7. [Lambda Layers](#lambda-layers)
8. [VPC Integration](#vpc-integration)
9. [Monitoring and Debugging](#monitoring-and-debugging)
10. [Best Practices](#best-practices)
11. [Interview Questions](#interview-questions)

---

## Lambda Architecture

### Lambda Execution Model

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                    LAMBDA SERVICE                        │
                                    │                                                          │
 ┌──────────────┐   Invoke         │  ┌─────────────────────────────────────────────────┐   │
 │   API GW     │──────────────────│─▶│              EXECUTION ENVIRONMENT               │   │
 │   S3         │                  │  │                                                   │   │
 │   SNS/SQS    │                  │  │  ┌───────────────┐  ┌───────────────────────┐   │   │
 │   EventBridge│                  │  │  │    INIT       │  │      INVOKE           │   │   │
 │   CloudWatch │                  │  │  │               │  │                       │   │   │
 │   etc.       │                  │  │  │ • Download    │  │ • Execute handler     │   │   │
 └──────────────┘                  │  │  │   code        │  │ • Process event       │   │   │
                                   │  │  │ • Init runtime│  │ • Return response     │   │   │
                                   │  │  │ • Run init    │  │                       │   │   │
                                   │  │  │   code        │  │                       │   │   │
                                   │  │  └───────────────┘  └───────────────────────┘   │   │
                                   │  │                                                   │   │
                                   │  │  ┌───────────────────────────────────────────┐   │   │
                                   │  │  │           /tmp (512MB - 10GB)              │   │   │
                                   │  │  │        Ephemeral Storage                   │   │   │
                                   │  │  └───────────────────────────────────────────┘   │   │
                                   │  │                                                   │   │
                                   │  └─────────────────────────────────────────────────┘   │
                                   │                                                          │
                                   │  ┌─────────────────────────────────────────────────┐   │
                                   │  │        EXECUTION ENVIRONMENT (Warm)             │   │
                                   │  │         (Reused for subsequent invocations)     │   │
                                   │  └─────────────────────────────────────────────────┘   │
                                   │                                                          │
                                   └──────────────────────────────────────────────────────────┘
```

### Lambda Limits

| Resource | Default Limit | Max (Adjustable) |
|----------|--------------|------------------|
| **Memory** | 128 MB | 10,240 MB |
| **Timeout** | 3 seconds | 15 minutes |
| **Concurrent Executions** | 1,000 | 10,000+ |
| **Deployment Package** | 50 MB (zip) | 250 MB (unzipped) |
| **Container Image** | N/A | 10 GB |
| **Ephemeral Storage** | 512 MB | 10 GB |
| **Environment Variables** | N/A | 4 KB |
| **Layers** | 5 | 5 |

---

## Function Configuration

### Complete Lambda Terraform Configuration

```hcl
# Lambda Function
resource "aws_lambda_function" "api" {
  function_name = "api-handler"
  role          = aws_iam_role.lambda.arn
  
  # Deployment package options:
  # Option 1: S3
  s3_bucket         = aws_s3_bucket.lambda.id
  s3_key            = "api-handler/${var.version}/function.zip"
  source_code_hash  = data.aws_s3_object.lambda_hash.body
  
  # Option 2: Local file
  # filename         = "function.zip"
  # source_code_hash = filebase64sha256("function.zip")
  
  # Option 3: Container image
  # package_type = "Image"
  # image_uri    = "${aws_ecr_repository.lambda.repository_url}:latest"
  
  handler = "index.handler"  # Not needed for container images
  runtime = "nodejs18.x"     # Not needed for container images
  
  # Architecture (ARM64 for cost savings)
  architectures = ["arm64"]
  
  # Resource allocation
  memory_size = 1024  # MB (also determines CPU)
  timeout     = 30    # seconds
  
  # Ephemeral storage
  ephemeral_storage {
    size = 512  # MB, can go up to 10240
  }
  
  # Environment variables
  environment {
    variables = {
      ENV        = var.environment
      LOG_LEVEL  = "info"
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }
  
  # VPC configuration (if needed)
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
  
  # Layers
  layers = [
    aws_lambda_layer_version.common.arn,
    "arn:aws:lambda:us-east-1:580247275435:layer:LambdaInsightsExtension-Arm64:2"
  ]
  
  # Enable X-Ray tracing
  tracing_config {
    mode = "Active"
  }
  
  # Reserved concurrency (optional)
  # reserved_concurrent_executions = 100
  
  # Dead letter queue
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
  
  tags = {
    Environment = var.environment
    Application = "api"
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda
  ]
}

# CloudWatch Log Group (create before Lambda)
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/api-handler"
  retention_in_days = 30
}

# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "lambda-api-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC access policy (if VPC enabled)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for application needs
resource "aws_iam_role_policy" "lambda_custom" {
  name = "lambda-custom"
  role = aws_iam_role.lambda.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.api_key.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}
```

### Provisioned Concurrency

```hcl
# Provisioned concurrency for consistent performance
resource "aws_lambda_provisioned_concurrency_config" "api" {
  function_name                     = aws_lambda_function.api.function_name
  provisioned_concurrent_executions = 10
  qualifier                         = aws_lambda_alias.live.name
}

# Lambda alias (required for provisioned concurrency)
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
  
  # Weighted routing for canary
  routing_config {
    additional_version_weights = {
      (aws_lambda_function.api_canary.version) = 0.1
    }
  }
}

# Auto-scaling for provisioned concurrency
resource "aws_appautoscaling_target" "lambda" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "function:${aws_lambda_function.api.function_name}:${aws_lambda_alias.live.name}"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  service_namespace  = "lambda"
}

resource "aws_appautoscaling_policy" "lambda" {
  name               = "utilization"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.lambda.service_namespace
  resource_id        = aws_appautoscaling_target.lambda.resource_id
  scalable_dimension = aws_appautoscaling_target.lambda.scalable_dimension
  
  target_tracking_scaling_policy_configuration {
    target_value = 0.7  # 70% utilization
    
    predefined_metric_specification {
      predefined_metric_type = "LambdaProvisionedConcurrencyUtilization"
    }
  }
}
```

---

## Triggers and Integrations

### API Gateway Integration

```hcl
# API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["https://example.com"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      path              = "$context.path"
      status            = "$context.status"
      responseLength    = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
```

### S3 Trigger

```hcl
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".csv"
  }
  
  depends_on = [aws_lambda_permission.s3]
}
```

### SQS Trigger

```hcl
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = aws_sqs_queue.main.arn
  function_name                      = aws_lambda_function.worker.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  
  # Scaling configuration
  scaling_config {
    maximum_concurrency = 100
  }
  
  # Error handling
  function_response_types = ["ReportBatchItemFailures"]
  
  filter_criteria {
    filter {
      pattern = jsonencode({
        body = {
          type = ["order", "payment"]
        }
      })
    }
  }
}
```

### EventBridge Trigger

```hcl
resource "aws_cloudwatch_event_rule" "cron" {
  name                = "daily-cleanup"
  description         = "Trigger Lambda daily at midnight"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.cron.name
  target_id = "CleanupLambda"
  arn       = aws_lambda_function.cleanup.arn
  
  input = jsonencode({
    action = "cleanup"
    type   = "daily"
  })
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}
```

---

## Cold Starts and Performance

### Cold Start Factors

| Factor | Impact | Mitigation |
|--------|--------|------------|
| **Language** | Python/Node fastest, Java/C# slowest | Choose optimal runtime |
| **Package Size** | Larger = slower | Minimize dependencies |
| **VPC** | Adds 1-10 seconds | Use VPC only if needed |
| **Memory** | More memory = more CPU | Increase memory |
| **Provisioned Concurrency** | Eliminates cold starts | Use for latency-sensitive |

### Cold Start Optimization

```python
# Python example - optimize initialization

import json
import boto3
import os

# Initialize outside handler (runs once during init)
# These persist between invocations
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

# Use connection pooling
from botocore.config import Config
config = Config(
    connect_timeout=5,
    read_timeout=10,
    max_pool_connections=10
)
s3_client = boto3.client('s3', config=config)

def handler(event, context):
    """Handler only contains business logic"""
    # Use pre-initialized resources
    response = table.get_item(Key={'id': event['id']})
    return {
        'statusCode': 200,
        'body': json.dumps(response.get('Item', {}))
    }
```

```javascript
// Node.js example - optimize initialization

const AWS = require('aws-sdk');

// Initialize outside handler
const dynamodb = new AWS.DynamoDB.DocumentClient({
  httpOptions: {
    connectTimeout: 5000,
    timeout: 10000
  },
  maxRetries: 3
});

const TABLE_NAME = process.env.TABLE_NAME;

// Cache expensive operations
let cachedConfig = null;
const getConfig = async () => {
  if (cachedConfig) return cachedConfig;
  
  const ssm = new AWS.SSM();
  const result = await ssm.getParameter({
    Name: '/app/config',
    WithDecryption: true
  }).promise();
  
  cachedConfig = JSON.parse(result.Parameter.Value);
  return cachedConfig;
};

exports.handler = async (event) => {
  const config = await getConfig();  // Uses cache
  
  const result = await dynamodb.get({
    TableName: TABLE_NAME,
    Key: { id: event.id }
  }).promise();
  
  return {
    statusCode: 200,
    body: JSON.stringify(result.Item)
  };
};
```

### Memory vs Duration Optimization

```
Memory(MB)  vCPU    Duration(ms)  Cost($)
---------------------------------------------
128         0.08    3000          0.0000062
256         0.17    1500          0.0000062
512         0.33    750           0.0000062
1024        0.67    375           0.0000062
2048        1.33    188           0.0000062
---------------------------------------------
Higher memory = more CPU = faster execution
Sweet spot is typically where duration * memory cost is minimized
```

---

## Concurrency and Scaling

### Concurrency Model

```
Account Concurrent Limit: 1000 (default)
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│Function │  │Function │  │Function │
│   A     │  │   B     │  │   C     │
│         │  │         │  │         │
│Reserved:│  │Reserved:│  │Unreserved│
│   200   │  │   100   │  │   Pool  │
└─────────┘  └─────────┘  └─────────┘
     │            │            │
     └────────────┴────────────┘
                  │
     Unreserved Pool: 700 (1000 - 200 - 100)
```

### Reserved Concurrency

```hcl
# Limit concurrency for downstream protection
resource "aws_lambda_function" "db_writer" {
  function_name = "db-writer"
  # ... configuration
  
  # Limit to 50 concurrent executions
  reserved_concurrent_executions = 50
}

# Set to 0 to disable function
resource "aws_lambda_function" "disabled" {
  function_name = "temporarily-disabled"
  reserved_concurrent_executions = 0
}
```

### SQS Scaling with MaxConcurrency

```hcl
resource "aws_lambda_event_source_mapping" "sqs_scaled" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.worker.arn
  
  # Limit Lambda scaling
  scaling_config {
    maximum_concurrency = 100  # Max 100 concurrent executions
  }
  
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
}
```

---

## Error Handling and Retries

### Retry Behavior by Trigger

| Trigger | Retry Behavior | Configurable |
|---------|----------------|--------------|
| **Sync (API GW)** | No retries | N/A |
| **Async (S3, SNS)** | 2 retries, then DLQ | Yes |
| **SQS** | Until visibility timeout | Redrive policy |
| **Kinesis/DynamoDB** | Until success or expiry | Error handling config |
| **EventBridge** | 1 retry, then DLQ | Yes |

### Error Handling Configuration

```hcl
# Async invocation configuration
resource "aws_lambda_function_event_invoke_config" "api" {
  function_name = aws_lambda_function.api.function_name
  
  maximum_event_age_in_seconds = 3600  # 1 hour
  maximum_retry_attempts       = 2
  
  destination_config {
    on_success {
      destination = aws_sqs_queue.success.arn
    }
    
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}
```

### Partial Batch Failure for SQS

```python
import json

def handler(event, context):
    batch_item_failures = []
    
    for record in event['Records']:
        try:
            # Process message
            message = json.loads(record['body'])
            process_message(message)
        except Exception as e:
            # Report individual failure
            batch_item_failures.append({
                'itemIdentifier': record['messageId']
            })
    
    return {
        'batchItemFailures': batch_item_failures
    }

def process_message(message):
    # Your processing logic
    pass
```

---

## Lambda Layers

### Creating a Layer

```hcl
# Layer for shared dependencies
resource "aws_lambda_layer_version" "common" {
  layer_name          = "common-dependencies"
  description         = "Common Python dependencies"
  compatible_runtimes = ["python3.9", "python3.10", "python3.11"]
  
  filename         = "layer.zip"
  source_code_hash = filebase64sha256("layer.zip")
}

# Using the layer
resource "aws_lambda_function" "api" {
  # ... other config
  
  layers = [
    aws_lambda_layer_version.common.arn,
    # AWS provided layer for Lambda Insights
    "arn:aws:lambda:${var.region}:580247275435:layer:LambdaInsightsExtension:21"
  ]
}
```

### Layer Directory Structure

```
layer.zip
└── python/
    ├── requests/
    ├── boto3/
    └── other_packages/

# Or for Node.js:
layer.zip
└── nodejs/
    └── node_modules/
        ├── axios/
        └── other_packages/
```

---

## VPC Integration

### When to Use VPC

| Use VPC | Don't Use VPC |
|---------|---------------|
| Access RDS/ElastiCache | Only need AWS APIs |
| Access internal services | Pure compute |
| Compliance requirements | Internet access needed |
| On-prem connectivity | Low latency required |

### VPC Configuration Best Practices

```hcl
resource "aws_lambda_function" "vpc_lambda" {
  function_name = "vpc-function"
  
  vpc_config {
    subnet_ids         = var.private_subnet_ids  # Multiple AZs
    security_group_ids = [aws_security_group.lambda.id]
  }
  
  # VPC Lambda needs this policy
  depends_on = [aws_iam_role_policy_attachment.lambda_vpc]
}

# Security group for Lambda
resource "aws_security_group" "lambda" {
  name   = "lambda-sg"
  vpc_id = var.vpc_id
  
  # Outbound to RDS
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }
  
  # Outbound to NAT for internet (AWS APIs)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## Monitoring and Debugging

### CloudWatch Metrics

```hcl
# Error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "lambda-${var.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Duration alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "lambda-${var.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 5000  # 5 seconds
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Throttles alarm
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "lambda-${var.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### CloudWatch Logs Insights Queries

```sql
-- Find errors
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- Cold starts
fields @timestamp, @type, @duration, @billedDuration
| filter @type = "REPORT"
| filter @message like /Init Duration/
| parse @message "Init Duration: * ms" as initDuration
| stats count(*) as coldStarts, avg(initDuration) as avgInit by bin(1h)

-- Duration percentiles
fields @timestamp, @duration
| filter @type = "REPORT"
| stats pct(@duration, 50) as p50, pct(@duration, 95) as p95, pct(@duration, 99) as p99 by bin(5m)

-- Memory usage
fields @timestamp, @maxMemoryUsed, @memorySize
| filter @type = "REPORT"
| stats avg(@maxMemoryUsed/@memorySize*100) as avgMemoryPct by bin(5m)
```

---

## Best Practices

### Production Checklist

| Category | Best Practice |
|----------|---------------|
| **Code** | Initialize outside handler, minimal dependencies |
| **Configuration** | Use appropriate memory, set reasonable timeout |
| **Security** | Least privilege IAM, use Secrets Manager |
| **Error Handling** | Configure DLQ, handle partial failures |
| **Monitoring** | Set up alarms for errors, duration, throttles |
| **Deployment** | Use aliases, implement canary deployments |
| **Cost** | Use ARM64, right-size memory, avoid over-provisioning |

---

## Interview Questions

### Q1: How do you optimize Lambda cold starts?

**Answer:**

1. **Language Choice:** Use Python/Node.js (faster init than Java/.NET)

2. **Package Size:** Minimize dependencies, use Lambda Layers

3. **Memory:** Increase memory = more CPU = faster init

4. **Provisioned Concurrency:** Pre-warm instances for consistent latency

5. **Code Optimization:**
   - Initialize SDK clients outside handler
   - Use connection pooling
   - Lazy load optional dependencies

6. **VPC:** Avoid VPC unless necessary (adds ~1-10s)

7. **ARM64:** Graviton2 processors initialize faster

---

### Q2: Explain Lambda concurrency models and when to use reserved vs provisioned concurrency.

**Answer:**

| Type | Purpose | Use Case | Cost |
|------|---------|----------|------|
| **Unreserved** | Shared pool across functions | Default, most functions | Standard |
| **Reserved** | Guaranteed capacity | Protect downstream, limit blast radius | No extra |
| **Provisioned** | Pre-initialized instances | Latency-sensitive, eliminate cold starts | Extra charge |

**Reserved Concurrency:**
- Set: `reserved_concurrent_executions = 50`
- Guarantees function can scale to 50
- Protects other functions from being starved
- Use to limit database connections

**Provisioned Concurrency:**
- Set: `provisioned_concurrent_executions = 10`
- Pre-warms 10 instances
- Eliminates cold starts for those 10
- Use for APIs with strict latency requirements

---

### Q3: How would you debug a Lambda function that's timing out?

**Answer:**

**Step 1: Check CloudWatch Logs**
```sql
fields @timestamp, @message, @duration
| filter @type = "REPORT"
| filter @duration > 25000
| sort @timestamp desc
```

**Step 2: Enable X-Ray**
```hcl
tracing_config {
  mode = "Active"
}
```
Identify slow segments in trace.

**Step 3: Common Causes:**
- Downstream service slow → Check RDS, external APIs
- DNS resolution in VPC → Check NAT Gateway
- Memory thrashing → Increase memory
- Cold start + slow init → Use provisioned concurrency

**Step 4: Add Structured Logging**
```python
import time

def handler(event, context):
    start = time.time()
    
    # DB call
    db_start = time.time()
    result = db.query(...)
    print(f"DB query took: {time.time() - db_start}s")
    
    # API call
    api_start = time.time()
    response = external_api.call(...)
    print(f"API call took: {time.time() - api_start}s")
    
    print(f"Total execution: {time.time() - start}s")
```
