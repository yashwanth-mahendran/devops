# AWS Monitoring and Alerting Deep Dive

Complete guide to CloudWatch, alerting strategies, and observability best practices.

---

## Table of Contents

1. [Observability Strategy](#observability-strategy)
2. [CloudWatch Metrics](#cloudwatch-metrics)
3. [CloudWatch Logs](#cloudwatch-logs)
4. [CloudWatch Alarms](#cloudwatch-alarms)
5. [Alerting Best Practices](#alerting-best-practices)
6. [Dashboards](#dashboards)
7. [X-Ray Tracing](#x-ray-tracing)
8. [Synthetic Monitoring](#synthetic-monitoring)
9. [Cost Optimization](#cost-optimization)
10. [Interview Questions](#interview-questions)

---

## Observability Strategy

### Three Pillars of Observability

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          OBSERVABILITY PILLARS                                   │
│                                                                                  │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐     │
│  │       METRICS       │  │        LOGS         │  │       TRACES        │     │
│  │                     │  │                     │  │                     │     │
│  │ • CloudWatch Metrics│  │ • CloudWatch Logs   │  │ • AWS X-Ray         │     │
│  │ • Custom Metrics    │  │ • Log Insights      │  │ • Distributed       │     │
│  │ • Container Insights│  │ • Metric Filters    │  │   Tracing           │     │
│  │ • EMF               │  │ • Subscriptions     │  │ • Service Map       │     │
│  │                     │  │                     │  │                     │     │
│  │ WHAT is happening?  │  │ WHY is it happening?│  │ WHERE did it happen?│     │
│  │                     │  │                     │  │                     │     │
│  │ • Request count     │  │ • Error messages    │  │ • Request flow      │     │
│  │ • Latency           │  │ • Stack traces      │  │ • Service deps      │     │
│  │ • Error rate        │  │ • Debug info        │  │ • Bottlenecks       │     │
│  │ • Resource usage    │  │ • Audit trail       │  │ • Latency breakdown │     │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Monitoring Strategy

| Layer | Metrics | Tools |
|-------|---------|-------|
| **Infrastructure** | CPU, Memory, Disk, Network | CloudWatch, Container Insights |
| **Application** | Request rate, Latency, Errors | Custom metrics, EMF |
| **Business** | Orders, Revenue, Users | Custom metrics |
| **Synthetic** | Availability, Response time | CloudWatch Synthetics |

---

## CloudWatch Metrics

### Custom Metrics with EMF (Embedded Metric Format)

```python
# Python EMF example
import json
import datetime

def create_emf_log(metrics_data):
    """Create EMF log for custom metrics"""
    emf_log = {
        "_aws": {
            "Timestamp": int(datetime.datetime.now().timestamp() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": "MyApplication",
                    "Dimensions": [["Environment", "Service"]],
                    "Metrics": [
                        {"Name": "OrderCount", "Unit": "Count"},
                        {"Name": "OrderValue", "Unit": "None"},
                        {"Name": "ProcessingTime", "Unit": "Milliseconds"}
                    ]
                }
            ]
        },
        "Environment": "production",
        "Service": "order-service",
        "OrderCount": metrics_data["order_count"],
        "OrderValue": metrics_data["order_value"],
        "ProcessingTime": metrics_data["processing_time"],
        "OrderId": metrics_data["order_id"]  # High cardinality - not a dimension
    }
    
    # Print to stdout - CloudWatch Logs will automatically extract metrics
    print(json.dumps(emf_log))
```

### Terraform Custom Metrics

```hcl
# CloudWatch custom metric alarm
resource "aws_cloudwatch_metric_alarm" "custom_orders" {
  alarm_name          = "high-order-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  alarm_description   = "Order failure rate is too high"
  
  metric_query {
    id          = "error_rate"
    expression  = "errors/orders*100"
    label       = "Error Rate"
    return_data = "true"
  }
  
  metric_query {
    id = "errors"
    metric {
      metric_name = "OrderErrors"
      namespace   = "MyApplication"
      period      = 60
      stat        = "Sum"
      dimensions = {
        Environment = "production"
      }
    }
  }
  
  metric_query {
    id = "orders"
    metric {
      metric_name = "OrderCount"
      namespace   = "MyApplication"
      period      = 60
      stat        = "Sum"
      dimensions = {
        Environment = "production"
      }
    }
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

---

## CloudWatch Logs

### Log Group Configuration

```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/api-service"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn
  
  tags = {
    Application = "api"
    Environment = "production"
  }
}

# Metric filter for errors
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "ErrorCount"
  pattern        = "[timestamp, request_id, level=ERROR, ...]"
  log_group_name = aws_cloudwatch_log_group.app.name
  
  metric_transformation {
    name          = "ErrorCount"
    namespace     = "MyApplication"
    value         = "1"
    default_value = "0"
    dimensions = {
      Service = "api"
    }
  }
}

# Metric filter for latency (from structured logs)
resource "aws_cloudwatch_log_metric_filter" "latency" {
  name           = "RequestLatency"
  pattern        = "{ $.duration_ms = * }"
  log_group_name = aws_cloudwatch_log_group.app.name
  
  metric_transformation {
    name      = "RequestLatency"
    namespace = "MyApplication"
    value     = "$.duration_ms"
    unit      = "Milliseconds"
  }
}

# Subscription filter for real-time processing
resource "aws_cloudwatch_log_subscription_filter" "errors_to_lambda" {
  name            = "errors-to-lambda"
  log_group_name  = aws_cloudwatch_log_group.app.name
  filter_pattern  = "ERROR"
  destination_arn = aws_lambda_function.error_processor.arn
}
```

### CloudWatch Logs Insights Queries

```sql
-- Find most common errors
fields @timestamp, @message
| filter @message like /ERROR/
| parse @message "ERROR: *" as errorMessage
| stats count(*) as errorCount by errorMessage
| sort errorCount desc
| limit 10

-- Latency percentiles
fields @timestamp, @message
| filter @message like /duration/
| parse @message 'duration_ms": *,' as duration
| stats pct(duration, 50) as p50, 
        pct(duration, 95) as p95, 
        pct(duration, 99) as p99 
  by bin(5m)

-- Find slow requests
fields @timestamp, @message
| filter @message like /duration/
| parse @message 'duration_ms": *,' as duration
| filter duration > 5000
| sort @timestamp desc
| limit 100

-- Error rate by service
fields @timestamp, @message
| filter @message like /level/
| parse @message 'level": "*"' as level
| parse @message 'service": "*"' as service
| stats count(*) as total,
        sum(level="ERROR") as errors,
        (sum(level="ERROR")/count(*))*100 as error_rate
  by service
| sort error_rate desc

-- Request tracing
fields @timestamp, @message
| filter @message like "request_id"
| parse @message 'request_id": "*"' as request_id
| filter request_id = "abc-123-xyz"
| sort @timestamp asc
```

---

## CloudWatch Alarms

### Multi-Layer Alarm Strategy

```hcl
# Critical: Service down
resource "aws_cloudwatch_metric_alarm" "service_down" {
  alarm_name          = "CRITICAL-api-service-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }
  
  alarm_actions = [
    aws_sns_topic.critical.arn,
    aws_sns_topic.pagerduty.arn
  ]
  
  treat_missing_data = "breaching"
}

# High: High error rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "HIGH-api-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 5  # 5% error rate
  
  metric_query {
    id          = "error_rate"
    expression  = "(m2/m1)*100"
    label       = "Error Rate %"
    return_data = true
  }
  
  metric_query {
    id = "m1"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }
  
  metric_query {
    id = "m2"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }
  
  alarm_actions = [aws_sns_topic.high.arn]
}

# Medium: High latency
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "MEDIUM-api-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2  # 2 seconds
  
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
  
  alarm_actions = [aws_sns_topic.medium.arn]
}

# Warning: Approaching capacity
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "WARNING-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CpuUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.api.name
  }
  
  alarm_actions = [aws_sns_topic.warning.arn]
}

# Composite alarm for nuanced alerting
resource "aws_cloudwatch_composite_alarm" "api_degraded" {
  alarm_name = "api-service-degraded"
  
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.high_latency.alarm_name})"
  ])
  
  alarm_actions         = [aws_sns_topic.high.arn]
  insufficient_data_actions = []
  ok_actions            = [aws_sns_topic.recovery.arn]
}
```

---

## Alerting Best Practices

### Alert Severity Levels

| Level | Criteria | Response Time | Notification |
|-------|----------|---------------|--------------|
| **Critical** | Service down, data loss risk | Immediate | PagerDuty, SMS |
| **High** | Degraded service, high error rate | 15 minutes | Slack, Email |
| **Medium** | Performance issues | 1 hour | Slack |
| **Warning** | Approaching thresholds | Next business day | Email |

### Alert Configuration

```hcl
# SNS Topics for different severities
resource "aws_sns_topic" "critical" {
  name = "critical-alerts"
}

resource "aws_sns_topic" "high" {
  name = "high-alerts"
}

resource "aws_sns_topic" "medium" {
  name = "medium-alerts"
}

resource "aws_sns_topic" "warning" {
  name = "warning-alerts"
}

# PagerDuty integration for critical
resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn = aws_sns_topic.critical.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/integration/${var.pagerduty_key}/enqueue"
}

# Slack integration via Lambda
resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.high.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

# Slack notification Lambda
resource "aws_lambda_function" "slack_notifier" {
  function_name = "slack-alerter"
  runtime       = "python3.11"
  handler       = "index.handler"
  
  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}
```

### Slack Notifier Lambda

```python
import json
import urllib.request
import os

def handler(event, context):
    slack_url = os.environ['SLACK_WEBHOOK_URL']
    
    for record in event['Records']:
        message = json.loads(record['Sns']['Message'])
        
        # Format CloudWatch alarm message
        alarm_name = message.get('AlarmName', 'Unknown')
        state = message.get('NewStateValue', 'Unknown')
        reason = message.get('NewStateReason', 'No reason provided')
        
        # Color based on state
        color = {
            'ALARM': '#FF0000',
            'OK': '#00FF00',
            'INSUFFICIENT_DATA': '#FFFF00'
        }.get(state, '#808080')
        
        slack_message = {
            "attachments": [
                {
                    "color": color,
                    "title": f"🚨 {alarm_name}",
                    "fields": [
                        {"title": "State", "value": state, "short": True},
                        {"title": "Region", "value": message.get('Region', 'N/A'), "short": True},
                        {"title": "Reason", "value": reason, "short": False}
                    ],
                    "footer": "CloudWatch Alarm",
                    "ts": int(datetime.datetime.now().timestamp())
                }
            ]
        }
        
        req = urllib.request.Request(
            slack_url,
            data=json.dumps(slack_message).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        urllib.request.urlopen(req)
    
    return {'statusCode': 200}
```

---

## Dashboards

### Terraform Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "api-service-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Key Metrics
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Request Count"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Response Time"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Error Rate"
          region  = var.region
          metrics = [
            [{
              expression = "(m2/m1)*100"
              label      = "5XX Error Rate %"
              id         = "e1"
            }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { id = "m1", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { id = "m2", visible = false }]
          ]
          period = 60
          view   = "timeSeries"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Healthy Hosts"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.api.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Average"
          view   = "singleValue"
        }
      },
      
      # Row 2: ECS Metrics
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ECS CPU Utilization"
          region  = var.region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.api.name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          annotations = {
            horizontal = [
              { value = 80, label = "Warning" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ECS Memory Utilization"
          region  = var.region
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.api.name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ECS Task Count"
          region  = var.region
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.api.name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      
      # Row 3: Database Metrics
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU"
          region  = var.region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS Connections"
          region  = var.region
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS Latency"
          region  = var.region
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", aws_db_instance.main.identifier, { label = "Read" }],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", aws_db_instance.main.identifier, { label = "Write" }]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      
      # Row 4: Logs and Alarms
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Recent Errors"
          region = var.region
          query  = "SOURCE '/ecs/api-service' | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.service_down.arn,
            aws_cloudwatch_metric_alarm.high_error_rate.arn,
            aws_cloudwatch_metric_alarm.high_latency.arn,
            aws_cloudwatch_metric_alarm.high_cpu.arn
          ]
        }
      }
    ]
  })
}
```

---

## X-Ray Tracing

### Enable X-Ray in Lambda

```hcl
resource "aws_lambda_function" "api" {
  function_name = "api-handler"
  
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      AWS_XRAY_DAEMON_ADDRESS = "localhost:2000"
    }
  }
}
```

### X-Ray in ECS

```hcl
# Add X-Ray sidecar to task definition
resource "aws_ecs_task_definition" "api" {
  family = "api-service"
  
  container_definitions = jsonencode([
    {
      name  = "api"
      image = "my-app:latest"
      
      environment = [
        { name = "AWS_XRAY_DAEMON_ADDRESS", value = "localhost:2000" }
      ]
    },
    {
      name  = "xray-daemon"
      image = "amazon/aws-xray-daemon:latest"
      
      portMappings = [
        { containerPort = 2000, protocol = "udp" }
      ]
      
      cpu    = 32
      memory = 256
    }
  ])
}
```

---

## Synthetic Monitoring

### CloudWatch Synthetics Canary

```hcl
resource "aws_synthetics_canary" "api_health" {
  name                 = "api-health-check"
  artifact_s3_location = "s3://${aws_s3_bucket.synthetics.id}/canary/"
  execution_role_arn   = aws_iam_role.synthetics.arn
  handler              = "apiCanaryBlueprint.handler"
  runtime_version      = "syn-nodejs-puppeteer-6.1"
  
  schedule {
    expression = "rate(5 minutes)"
  }
  
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.synthetics.id]
  }
  
  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 960
    active_tracing     = true
  }
  
  zip_file = data.archive_file.canary.output_base64sha256
}

# Alarm on canary failure
resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name          = "api-canary-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  
  dimensions = {
    CanaryName = aws_synthetics_canary.api_health.name
  }
  
  alarm_actions = [aws_sns_topic.critical.arn]
}
```

---

## Interview Questions

### Q1: How would you set up alerting for a microservices architecture with 50+ services?

**Answer:**

**Strategy: Hierarchical alerting with standardization**

1. **Standardize metrics:**
   - All services emit RED metrics (Rate, Errors, Duration)
   - Use EMF for consistent custom metrics
   - Standard naming: `{service}/RequestCount`, `{service}/ErrorRate`

2. **Alert hierarchy:**
   ```
   Level 1: Service-specific (owner)
   Level 2: Domain/team aggregate
   Level 3: Platform-wide SLO
   ```

3. **Implementation:**
   ```hcl
   # Terraform module for standardized alerts
   module "service_alerts" {
     source = "./modules/service-alerts"
     
     for_each = var.services
     
     service_name     = each.key
     error_threshold  = 5
     latency_p99      = 500
     team_sns_topic   = each.value.team_topic
   }
   ```

4. **Reduce noise:**
   - Composite alarms for correlated failures
   - Anomaly detection instead of static thresholds
   - Deduplication with correlation IDs

---

### Q2: Your CloudWatch costs are $10,000/month. How would you reduce this?

**Answer:**

**Cost analysis:**
1. **Logs (usually 60-70%):** 
   - Reduce retention: 30 days → 7 days for non-critical
   - Filter unnecessary logs at source
   - Use log sampling in high-volume services

2. **Custom metrics (usually 20-30%):**
   - Remove unused metrics
   - Reduce dimensions (high cardinality)
   - Use EMF instead of PutMetricData (cheaper)

3. **Dashboards and alarms:**
   - Consolidate duplicate dashboards
   - Remove orphaned alarms

**Implementation:**
```hcl
# Log retention policy
resource "aws_cloudwatch_log_group" "app" {
  retention_in_days = 7  # Not 30 for non-critical
}

# Metric filter instead of PutMetricData
resource "aws_cloudwatch_log_metric_filter" "errors" {
  # Extract metrics from logs - cheaper than custom metrics
}

# S3 for long-term log storage
resource "aws_cloudwatch_log_subscription_filter" "to_s3" {
  destination_arn = aws_kinesis_firehose_delivery_stream.logs.arn
}
```
