# Amazon ECS - Deep Dive Guide

Complete guide to ECS architecture, deployment patterns, and troubleshooting.

---

## Table of Contents

1. [ECS Architecture](#ecs-architecture)
2. [Task Definitions](#task-definitions)
3. [Services and Deployments](#services-and-deployments)
4. [Capacity Providers](#capacity-providers)
5. [Networking Modes](#networking-modes)
6. [Service Discovery](#service-discovery)
7. [Logging and Monitoring](#logging-and-monitoring)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Interview Questions](#interview-questions)

---

## ECS Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              ECS ARCHITECTURE                                    │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐│
│  │                           ECS CLUSTER                                      ││
│  │                                                                            ││
│  │  ┌───────────────────────────────┐  ┌───────────────────────────────┐     ││
│  │  │       CAPACITY PROVIDERS      │  │          SERVICES             │     ││
│  │  │                               │  │                               │     ││
│  │  │  ┌─────────┐  ┌─────────┐    │  │  ┌─────────┐  ┌─────────┐    │     ││
│  │  │  │ FARGATE │  │FARGATE  │    │  │  │ Service │  │ Service │    │     ││
│  │  │  │         │  │  SPOT   │    │  │  │    A    │  │    B    │    │     ││
│  │  │  └─────────┘  └─────────┘    │  │  └────┬────┘  └────┬────┘    │     ││
│  │  │                               │  │       │            │         │     ││
│  │  │  ┌─────────┐  ┌─────────┐    │  │       ▼            ▼         │     ││
│  │  │  │   EC2   │  │   EC2   │    │  │  ┌─────────────────────┐    │     ││
│  │  │  │   ASG   │  │  SPOT   │    │  │  │       TASKS         │    │     ││
│  │  │  └─────────┘  └─────────┘    │  │  │                     │    │     ││
│  │  │                               │  │  │ [Task] [Task] [Task]│    │     ││
│  │  └───────────────────────────────┘  │  └─────────────────────┘    │     ││
│  │                                      │                             │     ││
│  │                                      └───────────────────────────────┘     ││
│  │                                                                            ││
│  │  ┌───────────────────────────────────────────────────────────────────────┐││
│  │  │                      TASK DEFINITIONS                                 │││
│  │  │                                                                       │││
│  │  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐       │││
│  │  │  │   Container 1   │  │   Container 2   │  │   Container 3   │       │││
│  │  │  │   (App)        │  │   (Sidecar)     │  │   (Log Router)  │       │││
│  │  │  │                │  │                 │  │                 │       │││
│  │  │  │ CPU: 512       │  │ CPU: 256        │  │ CPU: 256        │       │││
│  │  │  │ Memory: 1024   │  │ Memory: 512     │  │ Memory: 512     │       │││
│  │  │  └─────────────────┘  └─────────────────┘  └─────────────────┘       │││
│  │  │                                                                       │││
│  │  └───────────────────────────────────────────────────────────────────────┘││
│  │                                                                            ││
│  └────────────────────────────────────────────────────────────────────────────┘│
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### ECS vs EKS Comparison

| Feature | ECS | EKS |
|---------|-----|-----|
| **Complexity** | Simpler, AWS-native | More complex, Kubernetes |
| **Flexibility** | AWS ecosystem | Multi-cloud portable |
| **Learning Curve** | Lower | Higher |
| **Cost** | Free control plane | $0.10/hour/cluster |
| **Community** | AWS focused | Large K8s ecosystem |
| **Best For** | AWS-centric teams | K8s expertise, multi-cloud |

---

## Task Definitions

### Complete Task Definition Example

```json
{
  "family": "api-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  
  "containerDefinitions": [
    {
      "name": "api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/api:v1.2.3",
      "essential": true,
      "cpu": 768,
      "memory": 1536,
      "memoryReservation": 1024,
      
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      
      "environment": [
        {"name": "ENV", "value": "production"},
        {"name": "LOG_LEVEL", "value": "info"}
      ],
      
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-password"
        },
        {
          "name": "API_KEY",
          "valueFrom": "arn:aws:ssm:us-east-1:123456789012:parameter/prod/api-key"
        }
      ],
      
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/api-service",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "api"
        }
      },
      
      "linuxParameters": {
        "initProcessEnabled": true
      },
      
      "ulimits": [
        {
          "name": "nofile",
          "softLimit": 65536,
          "hardLimit": 65536
        }
      ],
      
      "dependsOn": [
        {
          "containerName": "datadog-agent",
          "condition": "START"
        }
      ]
    },
    
    {
      "name": "datadog-agent",
      "image": "public.ecr.aws/datadog/agent:latest",
      "essential": false,
      "cpu": 256,
      "memory": 512,
      
      "environment": [
        {"name": "ECS_FARGATE", "value": "true"},
        {"name": "DD_APM_ENABLED", "value": "true"},
        {"name": "DD_APM_NON_LOCAL_TRAFFIC", "value": "true"}
      ],
      
      "secrets": [
        {
          "name": "DD_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:datadog-api-key"
        }
      ],
      
      "portMappings": [
        {"containerPort": 8126, "protocol": "tcp"},
        {"containerPort": 8125, "protocol": "udp"}
      ]
    }
  ],
  
  "volumes": [
    {
      "name": "efs-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-12345678",
        "rootDirectory": "/data",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "fsap-12345678"
        }
      }
    }
  ],
  
  "tags": [
    {"key": "Environment", "value": "production"},
    {"key": "Application", "value": "api"}
  ]
}
```

### Terraform Task Definition

```hcl
resource "aws_ecs_task_definition" "api" {
  family                   = "api-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  
  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
      essential = true
      cpu       = 768
      memory    = 1536
      
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      
      environment = [
        { name = "ENV", value = var.environment }
      ]
      
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "api"
        }
      }
      
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])
  
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"  # Cost optimization with Graviton
  }
}
```

---

## Services and Deployments

### ECS Service with Blue/Green Deployment

```hcl
resource "aws_ecs_service" "api" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 4
  launch_type     = "FARGATE"
  
  # Platform version (use latest)
  platform_version = "1.4.0"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.api_blue.arn
    container_name   = "api"
    container_port   = 8080
  }
  
  # Blue/Green deployment with CodeDeploy
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  
  # Enable execute command for debugging
  enable_execute_command = true
  
  # Service discovery
  service_registries {
    registry_arn   = aws_service_discovery_service.api.arn
    container_name = "api"
  }
  
  # Propagate tags from service to tasks
  propagate_tags = "SERVICE"
  
  tags = {
    Application = "api"
    Environment = var.environment
  }
  
  lifecycle {
    ignore_changes = [
      task_definition,  # Managed by CodeDeploy
      load_balancer,    # Managed by CodeDeploy
    ]
  }
}

# CodeDeploy for Blue/Green
resource "aws_codedeploy_app" "api" {
  name             = "api-ecs"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "api" {
  app_name               = aws_codedeploy_app.api.name
  deployment_group_name  = "api-deployment"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  
  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.api.name
  }
  
  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
    
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
  }
  
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.https.arn]
      }
      
      test_traffic_route {
        listener_arns = [aws_lb_listener.test.arn]
      }
      
      target_group {
        name = aws_lb_target_group.api_blue.name
      }
      
      target_group {
        name = aws_lb_target_group.api_green.name
      }
    }
  }
  
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
  
  alarm_configuration {
    alarms  = [aws_cloudwatch_metric_alarm.api_5xx.alarm_name]
    enabled = true
  }
}
```

### Rolling Deployment Configuration

```hcl
resource "aws_ecs_service" "api_rolling" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 4
  
  deployment_controller {
    type = "ECS"  # Rolling deployment
  }
  
  deployment_configuration {
    maximum_percent         = 200  # Deploy 4 new before removing old
    minimum_healthy_percent = 100  # Never go below desired count
  }
  
  # Circuit breaker (automatic rollback)
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  
  # Health check grace period
  health_check_grace_period_seconds = 60
}
```

---

## Capacity Providers

### Fargate with Spot Strategy

```hcl
resource "aws_ecs_cluster" "main" {
  name = "production"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  
  capacity_providers = [
    "FARGATE",
    "FARGATE_SPOT"
  ]
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 2      # Always run 2 on regular Fargate
    weight            = 1
  }
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = 3      # 3x more likely to use Spot
  }
}

# Service using capacity provider strategy
resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 8
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 2
    weight            = 1
  }
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = 3
  }
  
  # ... rest of configuration
}
```

### EC2 Capacity Provider with Auto Scaling

```hcl
# Auto Scaling Group
resource "aws_autoscaling_group" "ecs" {
  name                = "ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = 2
  max_size            = 20
  desired_capacity    = 4
  
  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }
  
  # Required for capacity provider
  protect_from_scale_in = true
  
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# Capacity Provider
resource "aws_ecs_capacity_provider" "ec2" {
  name = "ec2-capacity-provider"
  
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    
    managed_scaling {
      maximum_scaling_step_size = 5
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 80  # Target 80% utilization
    }
  }
}
```

---

## Networking Modes

### Network Mode Comparison

| Mode | Use Case | Pros | Cons |
|------|----------|------|------|
| **awsvpc** | Fargate, most EC2 | ENI per task, SG per task | ENI limits on EC2 |
| **bridge** | EC2 only | Dynamic port mapping | Shared network stack |
| **host** | EC2 only | Best performance | Port conflicts |
| **none** | Special cases | Complete isolation | No networking |

### awsvpc Mode (Recommended)

```hcl
# Task definition
resource "aws_ecs_task_definition" "api" {
  family       = "api"
  network_mode = "awsvpc"  # Each task gets its own ENI
  
  # ... container definitions
}

# Service with awsvpc networking
resource "aws_ecs_service" "api" {
  name = "api"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.api_tasks.id]
    assign_public_ip = false
  }
  
  # ... rest of config
}

# Security group for tasks
resource "aws_security_group" "api_tasks" {
  name   = "api-tasks-sg"
  vpc_id = var.vpc_id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "From ALB"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## Service Discovery

### AWS Cloud Map Integration

```hcl
# Private DNS namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "internal.local"
  description = "Private DNS namespace for ECS service discovery"
  vpc         = var.vpc_id
}

# Service discovery service
resource "aws_service_discovery_service" "api" {
  name = "api"
  
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    
    dns_records {
      ttl  = 10
      type = "A"  # For awsvpc mode
    }
    
    routing_policy = "MULTIVALUE"
  }
  
  health_check_custom_config {
    failure_threshold = 1
  }
}

# ECS service with service discovery
resource "aws_ecs_service" "api" {
  name = "api"
  
  service_registries {
    registry_arn   = aws_service_discovery_service.api.arn
    container_name = "api"
    container_port = 8080
  }
}

# Other services can now call: api.internal.local
```

---

## Logging and Monitoring

### CloudWatch Container Insights

```hcl
# Enable Container Insights
resource "aws_ecs_cluster" "main" {
  name = "production"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Log group for application
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/api-service"
  retention_in_days = 30
  
  tags = {
    Application = "api"
  }
}

# Metric alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "ecs-api-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CpuUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = "api-service"
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "ecs-api-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = "api-service"
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Task count alarm
resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  alarm_name          = "ecs-api-task-count-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = "api-service"
  }
  
  alarm_actions = [aws_sns_topic.critical.arn]
}
```

---

## Troubleshooting

### Common ECS Issues

#### Issue 1: Tasks Keep Failing to Start

```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster production \
  --tasks arn:aws:ecs:... \
  --query 'tasks[].{status:lastStatus,reason:stoppedReason,container:containers[].reason}'

# Common reasons:
# - "ResourceInitializationError: unable to pull secrets" → IAM permissions
# - "CannotPullContainerError" → ECR permissions or image doesn't exist
# - "OutOfMemoryError" → Increase memory
# - "HealthCheck" → Fix health check endpoint
```

#### Issue 2: Service Not Starting Desired Tasks

```bash
# Check service events
aws ecs describe-services \
  --cluster production \
  --services api-service \
  --query 'services[].events[:10]'

# Common issues:
# - No resources → Check capacity provider
# - Security group issues → Verify SG allows ALB traffic
# - Target group health check failing → Check endpoint
```

#### Issue 3: Tasks Running but Not Receiving Traffic

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Check task networking
aws ecs describe-tasks \
  --cluster production \
  --tasks <task-arn> \
  --query 'tasks[].attachments[].details'

# Verify security group
aws ec2 describe-security-groups \
  --group-ids sg-xxx
```

### ECS Exec for Debugging

```bash
# Enable ECS Exec on service (must be configured in Terraform)
# Then connect to running container:

aws ecs execute-command \
  --cluster production \
  --task <task-id> \
  --container api \
  --interactive \
  --command "/bin/sh"

# From inside container:
curl localhost:8080/health
cat /proc/1/environ | tr '\0' '\n'
netstat -tlnp
```

---

## Best Practices

### Production Checklist

| Category | Best Practice |
|----------|---------------|
| **Task Definition** | Use specific image tags, not latest |
| **Resources** | Set both CPU and memory limits |
| **Health Checks** | Configure container health checks |
| **Logging** | Use awslogs driver with retention |
| **Secrets** | Use Secrets Manager or SSM, never env vars |
| **Security** | Minimal IAM permissions, specific security groups |
| **Networking** | Use awsvpc mode, private subnets |
| **Deployment** | Enable circuit breaker, use blue/green |
| **Scaling** | Configure target tracking auto-scaling |
| **Monitoring** | Enable Container Insights |

### Cost Optimization

```hcl
# 1. Use Fargate Spot for non-critical workloads
capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight            = 3
}

# 2. Use ARM64 (Graviton) for 20% cost savings
runtime_platform {
  operating_system_family = "LINUX"
  cpu_architecture        = "ARM64"
}

# 3. Right-size tasks
# Monitor actual vs allocated CPU/Memory with Container Insights

# 4. Use Savings Plans
# Commit to Fargate usage for discounts
```

---

## Interview Questions

### Q1: Explain the difference between ECS Task Role and Task Execution Role.

**Answer:**

| Role | Purpose | Permissions |
|------|---------|-------------|
| **Task Execution Role** | Used by ECS agent | Pull images from ECR, fetch secrets, write logs |
| **Task Role** | Used by application | Application permissions (S3, DynamoDB, etc.) |

```json
// Task Execution Role - used by ECS service
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "*"
    }
  ]
}

// Task Role - used by application
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::my-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem"],
      "Resource": "arn:aws:dynamodb:*:*:table/my-table"
    }
  ]
}
```

---

### Q2: How would you debug an ECS task that's failing health checks?

**Answer:**

**Step-by-step debugging:**

1. **Check CloudWatch Logs:**
   ```bash
   aws logs tail /ecs/api-service --follow
   ```

2. **ECS Exec into container:**
   ```bash
   aws ecs execute-command --cluster prod --task xxx --container api --command "/bin/sh"
   # Then: curl localhost:8080/health
   ```

3. **Check target group health:**
   ```bash
   aws elbv2 describe-target-health --target-group-arn arn:aws:...
   ```

4. **Verify security groups allow traffic:**
   - ALB SG must allow outbound to task SG
   - Task SG must allow inbound from ALB SG

5. **Check health check configuration:**
   - Is the path correct?
   - Is the port correct?
   - Is the timeout sufficient?

---

### Q3: How do you handle zero-downtime deployments in ECS?

**Answer:**

**Option 1: Rolling deployment**
```hcl
deployment_configuration {
  maximum_percent         = 200
  minimum_healthy_percent = 100
}
deployment_circuit_breaker {
  enable   = true
  rollback = true
}
```

**Option 2: Blue/Green with CodeDeploy**
- Two target groups
- Traffic shifts gradually
- Automatic rollback on alarms

**Key requirements:**
1. Proper health checks (container + ALB)
2. Graceful shutdown handling (SIGTERM)
3. Health check grace period
4. Connection draining on target group
