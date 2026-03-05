# AWS High Availability Deep Dive

Complete guide to designing highly available architectures on AWS.

---

## Table of Contents

1. [HA Concepts](#ha-concepts)
2. [Multi-AZ Architecture](#multi-az-architecture)
3. [Auto Scaling](#auto-scaling)
4. [Load Balancing Strategies](#load-balancing-strategies)
5. [Database HA](#database-ha)
6. [Caching HA](#caching-ha)
7. [Health Checks](#health-checks)
8. [Failover Patterns](#failover-patterns)
9. [HA Checklist](#ha-checklist)
10. [Interview Questions](#interview-questions)

---

## HA Concepts

### Availability Targets

| Target | Downtime/Year | Downtime/Month | Downtime/Week |
|--------|---------------|----------------|---------------|
| 99% | 3.65 days | 7.2 hours | 1.68 hours |
| 99.9% | 8.76 hours | 43.8 minutes | 10.1 minutes |
| 99.95% | 4.38 hours | 21.9 minutes | 5.04 minutes |
| 99.99% | 52.6 minutes | 4.38 minutes | 1.01 minutes |
| 99.999% | 5.26 minutes | 26.3 seconds | 6.05 seconds |

### HA vs DR

| Aspect | High Availability | Disaster Recovery |
|--------|-------------------|-------------------|
| **Scope** | Component/Zone failure | Region/major failure |
| **RTO** | Seconds to minutes | Minutes to hours |
| **Cost** | Higher (always running) | Lower (standby) |
| **Data Loss** | Zero to minimal | RPO-based |
| **Complexity** | Moderate | Higher |

---

## Multi-AZ Architecture

### Three-AZ Production Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    REGION (us-east-1)                                │
│                                                                                      │
│  ┌──────────────────────────┬──────────────────────────┬──────────────────────────┐│
│  │      AZ-A (us-east-1a)  │      AZ-B (us-east-1b)   │      AZ-C (us-east-1c)   ││
│  │                         │                          │                          ││
│  │  ┌────────────────────┐ │  ┌────────────────────┐  │  ┌────────────────────┐  ││
│  │  │  Public Subnet     │ │  │  Public Subnet     │  │  │  Public Subnet     │  ││
│  │  │  10.0.1.0/24       │ │  │  10.0.2.0/24       │  │  │  10.0.3.0/24       │  ││
│  │  │                    │ │  │                    │  │  │                    │  ││
│  │  │  ┌──────────────┐  │ │  │  ┌──────────────┐  │  │  │  ┌──────────────┐  │  ││
│  │  │  │   NAT GW     │  │ │  │  │   NAT GW     │  │  │  │  │   NAT GW     │  │  ││
│  │  │  └──────────────┘  │ │  │  └──────────────┘  │  │  │  └──────────────┘  │  ││
│  │  └────────────────────┘ │  └────────────────────┘  │  └────────────────────┘  ││
│  │                         │                          │                          ││
│  │       ┌─────────────────┼──────────────────────────┼───────────────┐          ││
│  │       │           APPLICATION LOAD BALANCER                       │          ││
│  │       └─────────────────┼──────────────────────────┼───────────────┘          ││
│  │                         │                          │                          ││
│  │  ┌────────────────────┐ │  ┌────────────────────┐  │  ┌────────────────────┐  ││
│  │  │  Private Subnet    │ │  │  Private Subnet    │  │  │  Private Subnet    │  ││
│  │  │  10.0.10.0/24      │ │  │  10.0.20.0/24      │  │  │  10.0.30.0/24      │  ││
│  │  │                    │ │  │                    │  │  │                    │  ││
│  │  │  ┌──────────────┐  │ │  │  ┌──────────────┐  │  │  │  ┌──────────────┐  │  ││
│  │  │  │  App Server  │  │ │  │  │  App Server  │  │  │  │  │  App Server  │  │  ││
│  │  │  │  (ASG)       │  │ │  │  │  (ASG)       │  │  │  │  │  (ASG)       │  │  ││
│  │  │  └──────────────┘  │ │  │  └──────────────┘  │  │  │  └──────────────┘  │  ││
│  │  │                    │ │  │                    │  │  │                    │  ││
│  │  │  ┌──────────────┐  │ │  │  ┌──────────────┐  │  │  │  ┌──────────────┐  │  ││
│  │  │  │  ECS Task    │  │ │  │  │  ECS Task    │  │  │  │  │  ECS Task    │  │  ││
│  │  │  └──────────────┘  │ │  │  └──────────────┘  │  │  │  └──────────────┘  │  ││
│  │  └────────────────────┘ │  └────────────────────┘  │  └────────────────────┘  ││
│  │                         │                          │                          ││
│  │  ┌────────────────────┐ │  ┌────────────────────┐  │  ┌────────────────────┐  ││
│  │  │  Data Subnet       │ │  │  Data Subnet       │  │  │  Data Subnet       │  ││
│  │  │  10.0.100.0/24     │ │  │  10.0.200.0/24     │  │  │  10.0.250.0/24     │  ││
│  │  │                    │ │  │                    │  │  │                    │  ││
│  │  │  ┌──────────────┐  │ │  │  ┌──────────────┐  │  │  │                    │  ││
│  │  │  │  RDS Primary │◀─┼─┼──┼──│ RDS Standby  │  │  │  │  (Read Replica)    │  ││
│  │  │  └──────────────┘  │ │  │  └──────────────┘  │  │  │                    │  ││
│  │  │                    │ │  │                    │  │  │                    │  ││
│  │  │  ┌──────────────┐  │ │  │  ┌──────────────┐  │  │  │  ┌──────────────┐  │  ││
│  │  │  │ Redis Primary│◀─┼─┼──┼──│ Redis Rep    │──┼──┼──┼──│ Redis Rep    │  │  ││
│  │  │  └──────────────┘  │ │  │  └──────────────┘  │  │  │  └──────────────┘  │  ││
│  │  └────────────────────┘ │  └────────────────────┘  │  └────────────────────┘  ││
│  │                         │                          │                          ││
│  └─────────────────────────┴──────────────────────────┴──────────────────────────┘│
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Infrastructure as Code

```hcl
# VPC with 3 AZs
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "production-vpc"
  cidr = "10.0.0.0/16"
  
  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets  = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  database_subnets = ["10.0.100.0/24", "10.0.200.0/24", "10.0.250.0/24"]
  
  enable_nat_gateway     = true
  single_nat_gateway     = false  # One per AZ for HA
  one_nat_gateway_per_az = true
  
  enable_dns_hostnames = true
  enable_dns_support   = true
}
```

---

## Auto Scaling

### EC2 Auto Scaling Configuration

```hcl
resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [aws_lb_target_group.app.arn]
  
  min_size         = 3  # Minimum for HA
  max_size         = 15
  desired_capacity = 6
  
  # Health checks
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
      instance_warmup        = 300
    }
  }
  
  # Spread across AZs
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 3
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }
    
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app.id
        version            = "$Latest"
      }
      
      override {
        instance_type = "t3.medium"
      }
      override {
        instance_type = "t3a.medium"
      }
      override {
        instance_type = "t3.large"
      }
    }
  }
  
  # Lifecycle hooks for graceful operations
  initial_lifecycle_hook {
    name                    = "launch-hook"
    lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result          = "CONTINUE"
    heartbeat_timeout       = 300
    notification_target_arn = aws_sns_topic.asg_notifications.arn
    role_arn                = aws_iam_role.asg_lifecycle.arn
  }
  
  tag {
    key                 = "Name"
    value               = "app-server"
    propagate_at_launch = true
  }
}

# Scaling policies
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

resource "aws_autoscaling_policy" "request_count" {
  name                   = "request-count-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000.0
  }
}

# Scheduled scaling for known patterns
resource "aws_autoscaling_schedule" "scale_up_morning" {
  scheduled_action_name  = "scale-up-morning"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 6
  max_size               = 20
  desired_capacity       = 10
  recurrence             = "0 6 * * MON-FRI"  # 6 AM weekdays
  time_zone              = "America/New_York"
}

resource "aws_autoscaling_schedule" "scale_down_night" {
  scheduled_action_name  = "scale-down-night"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 3
  max_size               = 15
  desired_capacity       = 4
  recurrence             = "0 22 * * *"  # 10 PM daily
  time_zone              = "America/New_York"
}
```

### ECS Auto Scaling

```hcl
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 20
  min_capacity       = 3
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on CPU
resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "cpu-scaling"
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

# Scale on Memory
resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "memory-scaling"
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
```

---

## Load Balancing Strategies

### ALB with Health Checks

```hcl
resource "aws_lb" "app" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
  
  enable_deletion_protection = true
  enable_http2               = true
  idle_timeout               = 60
  
  # Cross-zone load balancing is always on for ALB
}

resource "aws_lb_target_group" "app" {
  name                 = "app-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "instance"  # or "ip" for Fargate
  deregistration_delay = 30
  
  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200-299"
  }
  
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false  # Disable for stateless apps
  }
}

# Listener with slow start
resource "aws_lb_target_group" "app_weighted" {
  name     = "app-tg-weighted"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  
  slow_start = 30  # 30 seconds to warm up
  
  health_check {
    path     = "/health"
    interval = 10
  }
}
```

### NLB for High Performance

```hcl
resource "aws_lb" "tcp" {
  name               = "tcp-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
  
  enable_cross_zone_load_balancing = true
  
  # Preserve source IP
}

resource "aws_lb_target_group" "tcp" {
  name                   = "tcp-tg"
  port                   = 9000
  protocol               = "TCP"
  vpc_id                 = module.vpc.vpc_id
  preserve_client_ip     = true
  connection_termination = true
  
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}
```

---

## Database HA

### RDS Multi-AZ

```hcl
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r6g.xlarge"
  
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Multi-AZ for HA
  multi_az = true
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  # Backup configuration
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  
  # Maintenance
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  
  # Performance
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  
  # Protection
  deletion_protection = true
  skip_final_snapshot = false
}

# Read Replica for read scaling
resource "aws_db_instance" "read_replica_1" {
  identifier     = "production-db-replica-1"
  instance_class = "db.r6g.large"
  
  replicate_source_db    = aws_db_instance.main.identifier
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  # Replica-specific settings
  backup_retention_period = 0  # Disable backups on replica
  skip_final_snapshot     = true
}
```

### Aurora HA

```hcl
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "production-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = "appdb"
  master_username    = "admin"
  master_password    = var.db_password
  
  # HA Configuration
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  
  # Backup
  backup_retention_period = 30
  preferred_backup_window = "03:00-04:00"
  
  # Storage encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
  
  # Protection
  deletion_protection = true
}

# Writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "production-aurora-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.xlarge"
  engine             = aws_rds_cluster.aurora.engine
  
  availability_zone = "us-east-1a"
  
  performance_insights_enabled = true
}

# Reader instances in other AZs
resource "aws_rds_cluster_instance" "readers" {
  count = 2
  
  identifier         = "production-aurora-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.aurora.engine
  
  availability_zone = element(["us-east-1b", "us-east-1c"], count.index)
  
  performance_insights_enabled = true
}
```

---

## Caching HA

### ElastiCache Redis Cluster Mode

```hcl
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "production-redis"
  description          = "Production Redis cluster"
  
  node_type            = "cache.r6g.large"
  num_cache_clusters   = 3  # 1 primary + 2 replicas
  port                 = 6379
  parameter_group_name = "default.redis7"
  
  # HA Configuration
  automatic_failover_enabled = true
  multi_az_enabled           = true
  
  # Networking
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  
  # Maintenance
  snapshot_retention_limit = 7
  snapshot_window          = "02:00-03:00"
  maintenance_window       = "mon:03:00-mon:04:00"
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = true
  
  # Notification
  notification_topic_arn = aws_sns_topic.redis_alerts.arn
}

# Redis Cluster Mode (sharding + replication)
resource "aws_elasticache_replication_group" "redis_cluster" {
  replication_group_id = "production-redis-cluster"
  description          = "Production Redis cluster mode"
  
  node_type                  = "cache.r6g.large"
  num_node_groups            = 3  # Shards
  replicas_per_node_group    = 2  # Replicas per shard
  port                       = 6379
  
  automatic_failover_enabled = true
  multi_az_enabled           = true
  
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
}
```

---

## Health Checks

### Multi-Layer Health Checks

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           HEALTH CHECK LAYERS                                    │
│                                                                                  │
│  Route 53 Health Check                                                          │
│  └── Check: https://api.example.com/health                                     │
│      └── Interval: 30s, Threshold: 3 failures                                  │
│                                                                                  │
│  CloudFront → Origin Health (via ALB)                                          │
│                                                                                  │
│  ALB Target Group Health Check                                                  │
│  └── Check: GET /health                                                        │
│      └── Interval: 10s, Unhealthy: 3, Healthy: 2                              │
│                                                                                  │
│  ECS Container Health Check                                                     │
│  └── Check: CMD-SHELL curl -f http://localhost:8080/health                     │
│      └── Interval: 30s, Timeout: 5s, Retries: 3                               │
│                                                                                  │
│  Application-Level Health Check                                                 │
│  └── /health endpoint checks:                                                  │
│      ├── Database connectivity                                                  │
│      ├── Redis connectivity                                                     │
│      ├── External service connectivity                                          │
│      └── Disk space / memory                                                    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Health Check Endpoint Example

```python
from flask import Flask, jsonify
import psycopg2
import redis
import requests

app = Flask(__name__)

@app.route('/health')
def health():
    """Basic health check - always returns 200 if app is running"""
    return jsonify({"status": "healthy"}), 200

@app.route('/health/ready')
def ready():
    """Readiness check - checks all dependencies"""
    checks = {
        "database": check_database(),
        "redis": check_redis(),
        "external_api": check_external_api()
    }
    
    all_healthy = all(check["healthy"] for check in checks.values())
    status_code = 200 if all_healthy else 503
    
    return jsonify({
        "status": "ready" if all_healthy else "not_ready",
        "checks": checks
    }), status_code

@app.route('/health/live')
def live():
    """Liveness check - app is alive and not deadlocked"""
    return jsonify({"status": "alive"}), 200

def check_database():
    try:
        conn = psycopg2.connect(os.environ['DATABASE_URL'])
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        conn.close()
        return {"healthy": True, "latency_ms": 0}
    except Exception as e:
        return {"healthy": False, "error": str(e)}

def check_redis():
    try:
        r = redis.Redis.from_url(os.environ['REDIS_URL'])
        r.ping()
        return {"healthy": True}
    except Exception as e:
        return {"healthy": False, "error": str(e)}

def check_external_api():
    try:
        response = requests.get(
            "https://api.external.com/health",
            timeout=5
        )
        return {
            "healthy": response.status_code == 200,
            "latency_ms": response.elapsed.total_seconds() * 1000
        }
    except Exception as e:
        return {"healthy": False, "error": str(e)}
```

---

## Failover Patterns

### Active-Passive Failover

```hcl
# Route 53 Failover
resource "aws_route53_health_check" "primary" {
  fqdn              = aws_lb.primary.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "primary-health-check"
  }
}

resource "aws_route53_record" "primary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "primary"
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary.id
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "secondary"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
}
```

---

## HA Checklist

### Production HA Checklist

| Component | HA Requirement | Implementation |
|-----------|----------------|----------------|
| **Compute** | Multi-AZ deployment | ASG/ECS across 3+ AZs |
| **Load Balancer** | Cross-zone enabled | ALB/NLB in public subnets |
| **Database** | Multi-AZ / Replication | RDS Multi-AZ or Aurora |
| **Cache** | Multi-AZ replication | ElastiCache with failover |
| **NAT Gateway** | Per-AZ deployment | One NAT GW per AZ |
| **DNS** | Health checks | Route 53 failover routing |
| **Secrets** | Regional service | Secrets Manager (regional HA built-in) |
| **Monitoring** | Multi-source | CloudWatch + third-party |

---

## Interview Questions

### Q1: Design a highly available architecture for an e-commerce application with 99.99% availability target.

**Answer:**

**Architecture Components:**

1. **Global Layer:**
   - CloudFront for static content
   - Route 53 with health checks
   - WAF for security

2. **Regional Layer (Primary):**
   - ALB across 3 AZs
   - ECS Fargate services (min 6 tasks, 2 per AZ)
   - Aurora PostgreSQL (writer + 2 readers)
   - ElastiCache Redis (3-node cluster)

3. **Regional Layer (DR):**
   - Warm standby with reduced capacity
   - Aurora Global Database for async replication

**Calculations:**
- 99.99% = 52.6 minutes downtime/year
- Each component must exceed 99.99%
- Avoid single points of failure

```
Availability = (1 - (1-0.9999)^3) for 3-AZ deployment
             = 99.9999997%
```

---

### Q2: How do you handle database failover without application changes?

**Answer:**

**Options:**

1. **RDS Multi-AZ:**
   - Automatic failover (1-2 minutes)
   - Same DNS endpoint
   - No application changes needed

2. **Aurora:**
   - Faster failover (30 seconds)
   - Reader endpoint for read scaling
   - Writer endpoint auto-updates

3. **RDS Proxy:**
   - Connection pooling
   - Failover handling
   - Less application reconnection logic

```hcl
resource "aws_db_proxy" "main" {
  name                   = "rds-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
    iam_auth    = "REQUIRED"
  }
}

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name
  
  connection_pool_config {
    max_connections_percent = 100
  }
}
```

**Application uses proxy endpoint:**
```
jdbc:postgresql://rds-proxy.proxy-xxxx.us-east-1.rds.amazonaws.com:5432/appdb
```
