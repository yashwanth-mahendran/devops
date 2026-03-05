# Three-Tier Architecture on AWS

Complete guide to designing, implementing, and scaling three-tier architectures.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Tier-by-Tier Deep Dive](#tier-by-tier-deep-dive)
3. [Scaling Strategies](#scaling-strategies)
4. [High Availability Design](#high-availability-design)
5. [Security Considerations](#security-considerations)
6. [Cost Optimization](#cost-optimization)
7. [Interview Questions](#interview-questions)

---

## Architecture Overview

### Classic Three-Tier Architecture

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                         REGION                              │
                                    │                                                             │
    Internet                        │   ┌─────────────────────────────────────────────────────┐  │
        │                           │   │                    PUBLIC SUBNETS                    │  │
        ▼                           │   │                                                      │  │
┌───────────────┐                   │   │   ┌─────────────┐         ┌─────────────┐          │  │
│   Route 53    │                   │   │   │  NAT GW     │         │  NAT GW     │          │  │
│  (DNS + HC)   │                   │   │   │  (AZ-A)     │         │  (AZ-B)     │          │  │
└───────┬───────┘                   │   │   └─────────────┘         └─────────────┘          │  │
        │                           │   │                                                      │  │
        ▼                           │   │   ┌───────────────────────────────────────────────┐ │  │
┌───────────────┐                   │   │   │        Application Load Balancer              │ │  │
│  CloudFront   │                   │   │   │              (Internet-facing)                │ │  │
│    (CDN)      │───────────────────│───│──►│                                               │ │  │
└───────────────┘                   │   │   └───────────────────────────────────────────────┘ │  │
                                    │   │                          │                          │  │
                                    │   └──────────────────────────┼──────────────────────────┘  │
                                    │                              │                             │
                                    │   ┌──────────────────────────┼──────────────────────────┐  │
                                    │   │              PRIVATE SUBNETS (APP TIER)              │  │
                                    │   │                          │                           │  │
                                    │   │         ┌────────────────┴────────────────┐         │  │
                                    │   │         │                                 │         │  │
                                    │   │         ▼                                 ▼         │  │
                                    │   │   ┌───────────┐                     ┌───────────┐  │  │
                                    │   │   │ Web ASG   │                     │ Web ASG   │  │  │
                                    │   │   │ (AZ-A)    │                     │ (AZ-B)    │  │  │
                                    │   │   │ [EC2/ECS] │                     │ [EC2/ECS] │  │  │
                                    │   │   └─────┬─────┘                     └─────┬─────┘  │  │
                                    │   │         │                                 │        │  │
                                    │   │         └────────────────┬────────────────┘        │  │
                                    │   │                          │                         │  │
                                    │   │   ┌───────────────────────────────────────────────┐│  │
                                    │   │   │         Internal Load Balancer                ││  │
                                    │   │   └───────────────────────────────────────────────┘│  │
                                    │   │                          │                         │  │
                                    │   │         ┌────────────────┴────────────────┐        │  │
                                    │   │         ▼                                 ▼        │  │
                                    │   │   ┌───────────┐                     ┌───────────┐ │  │
                                    │   │   │ App ASG   │                     │ App ASG   │ │  │
                                    │   │   │ (AZ-A)    │                     │ (AZ-B)    │ │  │
                                    │   │   │ [EC2/ECS] │                     │ [EC2/ECS] │ │  │
                                    │   │   └─────┬─────┘                     └─────┬─────┘ │  │
                                    │   │         │                                 │       │  │
                                    │   └─────────┼─────────────────────────────────┼───────┘  │
                                    │             │                                 │          │
                                    │   ┌─────────┼─────────────────────────────────┼───────┐  │
                                    │   │         │    PRIVATE SUBNETS (DATA TIER)  │       │  │
                                    │   │         │                                 │       │  │
                                    │   │         ▼                                 ▼       │  │
                                    │   │   ┌───────────────────────────────────────────┐  │  │
                                    │   │   │           RDS Multi-AZ                    │  │  │
                                    │   │   │     Primary (AZ-A) ↔ Standby (AZ-B)      │  │  │
                                    │   │   └───────────────────────────────────────────┘  │  │
                                    │   │                                                  │  │
                                    │   │   ┌───────────────────────────────────────────┐  │  │
                                    │   │   │        ElastiCache (Redis Cluster)        │  │  │
                                    │   │   │     Primary (AZ-A) ↔ Replica (AZ-B)       │  │  │
                                    │   │   └───────────────────────────────────────────┘  │  │
                                    │   │                                                  │  │
                                    │   └──────────────────────────────────────────────────┘  │
                                    │                                                         │
                                    └─────────────────────────────────────────────────────────┘
```

### Tier Responsibilities

| Tier | Components | Responsibility |
|------|------------|----------------|
| **Web/Presentation** | CloudFront, ALB, Web Servers | Handle user requests, SSL termination, static content |
| **Application/Logic** | EC2, ECS, Lambda | Business logic, API processing |
| **Data** | RDS, DynamoDB, ElastiCache | Data persistence, caching |

---

## Tier-by-Tier Deep Dive

### Tier 1: Presentation Layer

#### Components & Configuration

```hcl
# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  
  origin {
    domain_name = aws_lb.web.dns_name
    origin_id   = "alb"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  # Static assets from S3
  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id   = "s3-static"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }
  
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host"]
      cookies {
        forward = "all"
      }
    }
    
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0  # No caching for dynamic content
  }
  
  # Cache static assets
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    min_ttl     = 86400
    default_ttl = 604800
    max_ttl     = 31536000
    compress    = true
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.main.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Application Load Balancer
resource "aws_lb" "web" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  
  enable_deletion_protection = true
  enable_http2               = true
  
  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
```

#### Best Practices

| Aspect | Recommendation |
|--------|----------------|
| **SSL/TLS** | Use TLS 1.3, terminate at ALB or CloudFront |
| **Caching** | Cache static assets (images, JS, CSS) at CDN |
| **Compression** | Enable gzip/brotli at CloudFront |
| **Health Checks** | Configure path-based health checks |
| **WAF** | Enable AWS WAF on CloudFront/ALB |

---

### Tier 2: Application Layer

#### EC2-Based Configuration

```hcl
# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.medium"
  
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-cloudwatch-agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c ssm:${aws_ssm_parameter.cw_agent_config.name}
    
    # Install and start application
    aws s3 cp s3://${var.artifact_bucket}/${var.app_version}/app.tar.gz /tmp/
    tar -xzf /tmp/app.tar.gz -C /opt/app
    systemctl start app
    systemctl enable app
  EOF
  )
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  monitoring {
    enabled = true
  }
  
  metadata_options {
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "app-server"
      Environment = var.environment
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  desired_capacity    = 4
  min_size            = 2
  max_size            = 20
  vpc_zone_identifier = aws_subnet.private_app[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  tag {
    key                 = "Name"
    value               = "app-server"
    propagate_at_launch = true
  }
}

# Scaling Policies
resource "aws_autoscaling_policy" "app_scale_up" {
  name                   = "app-scale-up"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_policy" "app_target_tracking" {
  name                   = "app-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
```

#### ECS-Based Configuration

```hcl
# ECS Cluster with Capacity Providers
resource "aws_ecs_cluster" "main" {
  name = "app-cluster"
  
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
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 2  # Always run 2 on regular Fargate
  }
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 3  # Prefer Spot for additional tasks
  }
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 4
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 2
  }
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 3
  }
  
  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8080
  }
  
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
  
  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }
}
```

---

### Tier 3: Data Layer

#### RDS Configuration

```hcl
# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = aws_subnet.private_data[*].id
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "app-database"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r6g.xlarge"
  
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn
  
  db_name  = "appdb"
  username = "admin"
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
  
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  backup_retention_period   = 30
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  delete_automated_backups  = false
  copy_tags_to_snapshot     = true
  
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "app-database-final"
  
  parameter_group_name = aws_db_parameter_group.main.name
}

# Read Replica
resource "aws_db_instance" "read_replica" {
  identifier     = "app-database-replica"
  instance_class = "db.r6g.large"
  
  replicate_source_db = aws_db_instance.main.identifier
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn
}

# ElastiCache Redis
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "app-cache"
  description                = "Redis cluster for application caching"
  node_type                  = "cache.r6g.large"
  num_cache_clusters         = 2
  port                       = 6379
  
  automatic_failover_enabled = true
  multi_az_enabled           = true
  
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = data.aws_secretsmanager_secret_version.redis_token.secret_string
  
  snapshot_retention_limit = 7
  snapshot_window          = "02:00-03:00"
  
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
}
```

---

## Scaling Strategies

### Horizontal Scaling (Scale Out)

```
Load Increases → CloudWatch Alarm → Auto Scaling Policy → Add Instances
                                                        ↓
                    ← Load Balancer Updates Target Group ←
```

```hcl
# Application Auto Scaling for ECS
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 20
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "cpu-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "memory-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 70
  }
}

# Custom metric scaling (requests per target)
resource "aws_appautoscaling_policy" "ecs_requests" {
  name               = "requests-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000  # Requests per target
  }
}
```

### Vertical Scaling (Scale Up)

| Component | Current | Scaled Up | Use Case |
|-----------|---------|-----------|----------|
| EC2 | t3.medium | t3.xlarge | CPU-bound workloads |
| RDS | db.r6g.large | db.r6g.2xlarge | Database performance |
| ElastiCache | cache.r6g.medium | cache.r6g.xlarge | Cache hit rate issues |

---

## Security Considerations

### Network Segmentation

```hcl
# Security Group Architecture
# ALB → Web Tier → App Tier → Data Tier

# ALB Security Group
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}

# Web Tier Security Group
resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

# App Tier Security Group
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }
  
  egress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.redis.id]
  }
}
```

---

## Interview Questions

### Q1: Walk me through designing a three-tier architecture for a web application expecting 10,000 concurrent users.

**Answer:**

**Requirements Analysis:**
- 10,000 concurrent users
- Assume 100 requests/user/minute = ~16,000 requests/second peak
- 99.9% availability required

**Architecture:**
1. **Presentation Tier:**
   - CloudFront for static content and DDoS protection
   - Route 53 with health checks for DNS
   - ALB with WAF across 3 AZs
   - SSL termination at ALB

2. **Application Tier:**
   - ECS Fargate for containerized workloads
   - Auto-scaling: min 10, max 50 tasks
   - Service discovery for internal communication
   - Distributed across 3 AZs

3. **Data Tier:**
   - RDS PostgreSQL Multi-AZ for transactions
   - ElastiCache Redis cluster for session/caching
   - Read replicas for read-heavy operations

**Scaling Calculation:**
- If each container handles 500 req/s
- Need: 16,000 / 500 = 32 containers minimum
- With headroom: 40 containers

---

### Q2: How would you handle a sudden 10x traffic spike?

**Answer:**

**Immediate Response:**
1. **Pre-warmed capacity:** Keep minimum instances higher than baseline
2. **Step scaling:** Aggressive scale-out policies
3. **CloudFront:** Absorbs read traffic at edge
4. **Connection pooling:** RDS Proxy to manage database connections

**Configuration:**
```hcl
# Aggressive scaling for spikes
resource "aws_autoscaling_policy" "spike" {
  name                   = "spike-response"
  scaling_adjustment     = 10  # Add 10 instances immediately
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60  # Quick cooldown
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1  # React immediately
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.spike.arn]
}
```

---

### Q3: What are the trade-offs between using EC2 vs ECS/Fargate in the application tier?

**Answer:**

| Aspect | EC2 | ECS/Fargate |
|--------|-----|-------------|
| **Control** | Full OS control | Container only |
| **Scaling Speed** | Minutes | Seconds |
| **Cost** | Can be cheaper at scale | Pay per task, simpler |
| **Maintenance** | Patch OS, AMIs | AWS managed |
| **Complexity** | More operational overhead | Simpler operations |
| **Spot/Savings** | Spot instances, RIs | Fargate Spot |

**When to use EC2:**
- GPU workloads
- Specialized kernel requirements
- Existing VM-based applications
- Very cost-sensitive at high scale

**When to use ECS/Fargate:**
- Microservices
- Variable workloads
- Faster deployments
- Reduced operational overhead
