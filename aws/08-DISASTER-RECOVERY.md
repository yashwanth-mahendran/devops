# AWS Disaster Recovery Deep Dive

Complete guide to DR strategies, RTO/RPO planning, and failover procedures.

---

## Table of Contents

1. [DR Fundamentals](#dr-fundamentals)
2. [DR Strategies](#dr-strategies)
3. [Data Replication](#data-replication)
4. [Infrastructure as Code for DR](#infrastructure-as-code-for-dr)
5. [Testing DR](#testing-dr)
6. [Runbooks](#runbooks)
7. [Interview Questions](#interview-questions)

---

## DR Fundamentals

### RTO and RPO

```
                          DISASTER OCCURS
                                │
    ◄───────── RPO ────────────►│◄──────────── RTO ────────────►
    │                           │                               │
    │   Last Valid              │   Service                     │
    │   Backup/Sync             │   Restored                    │
    │                           │                               │
────┴───────────────────────────┴───────────────────────────────┴────►
                              Time

RPO (Recovery Point Objective): Maximum acceptable data loss
RTO (Recovery Time Objective): Maximum acceptable downtime
```

### DR Metrics by Strategy

| Strategy | RTO | RPO | Cost | Complexity |
|----------|-----|-----|------|------------|
| **Backup & Restore** | Hours | Hours | $ | Low |
| **Pilot Light** | 10-30 min | Minutes | $$ | Medium |
| **Warm Standby** | Minutes | Seconds | $$$ | Medium-High |
| **Multi-Site Active/Active** | Near-zero | Near-zero | $$$$ | High |

---

## DR Strategies

### Strategy 1: Backup and Restore

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                          BACKUP AND RESTORE                                     │
│                                                                                 │
│  PRIMARY REGION (us-east-1)              DR REGION (us-west-2)                │
│  ┌─────────────────────────┐             ┌─────────────────────────┐          │
│  │                         │             │                         │          │
│  │  ┌───────────────────┐  │             │  No infrastructure     │          │
│  │  │   EC2 + RDS       │  │             │  running (cold)        │          │
│  │  │   Application     │  │             │                         │          │
│  │  └─────────┬─────────┘  │             │  ┌───────────────────┐  │          │
│  │            │            │             │  │   S3 Backups      │  │          │
│  │            │ Backup     │             │  │   (Cross-region   │  │          │
│  │            ▼            │             │  │    replicated)    │  │          │
│  │  ┌───────────────────┐  │────────────▶│  └───────────────────┘  │          │
│  │  │   S3 Backups      │  │  Replicate  │                         │          │
│  │  │   RDS Snapshots   │  │             │  ┌───────────────────┐  │          │
│  │  └───────────────────┘  │             │  │   AMIs (copied)   │  │          │
│  │                         │             │  └───────────────────┘  │          │
│  │  ┌───────────────────┐  │             │                         │          │
│  │  │   AMIs            │──┼────────────▶│  On disaster:          │          │
│  │  └───────────────────┘  │  Copy       │  - Launch from AMIs    │          │
│  │                         │             │  - Restore from S3     │          │
│  └─────────────────────────┘             │  - Restore RDS         │          │
│                                          └─────────────────────────┘          │
│  RTO: 4-8 hours                          RPO: Last backup                     │
│  Cost: $                                                                       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

```hcl
# Cross-region backup replication
resource "aws_s3_bucket_replication_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-backups"
    status = "Enabled"
    
    destination {
      bucket        = "arn:aws:s3:::backup-bucket-dr-region"
      storage_class = "STANDARD_IA"
      
      encryption_configuration {
        replica_kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/dr-key"
      }
    }
    
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

# RDS automated backup to DR region
resource "aws_db_instance_automated_backups_replication" "dr" {
  source_db_instance_arn = aws_db_instance.main.arn
  kms_key_id             = aws_kms_key.dr.arn
  retention_period       = 14
  
  provider = aws.dr_region
}
```

### Strategy 2: Pilot Light

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              PILOT LIGHT                                        │
│                                                                                 │
│  PRIMARY REGION (us-east-1)              DR REGION (us-west-2)                │
│  ┌─────────────────────────┐             ┌─────────────────────────┐          │
│  │                         │             │                         │          │
│  │  ┌───────────────────┐  │             │  Infrastructure ready  │          │
│  │  │   ALB             │  │             │  but scaled to minimum │          │
│  │  └─────────┬─────────┘  │             │                         │          │
│  │            │            │             │  ┌───────────────────┐  │          │
│  │  ┌─────────▼─────────┐  │             │  │   ALB (ready)     │  │          │
│  │  │   ECS/EC2 (10)    │  │             │  └─────────┬─────────┘  │          │
│  │  └─────────┬─────────┘  │             │            │            │          │
│  │            │            │             │  ┌─────────▼─────────┐  │          │
│  │  ┌─────────▼─────────┐  │             │  │   ECS/EC2 (0-1)   │  │          │
│  │  │   Aurora Primary  │  │             │  └─────────┬─────────┘  │          │
│  │  └─────────┬─────────┘  │             │            │            │          │
│  │            │            │             │  ┌─────────▼─────────┐  │          │
│  │            │            │  Async      │  │   Aurora Replica  │  │          │
│  │            └────────────┼────────────▶│  │   (continuously   │  │          │
│  │                         │  Replication│  │    synced)        │  │          │
│  │                         │             │  └───────────────────┘  │          │
│  └─────────────────────────┘             └─────────────────────────┘          │
│                                                                                 │
│  On disaster:                                                                   │
│  1. Promote Aurora replica                                                     │
│  2. Scale up ECS/EC2 to production capacity                                   │
│  3. Update Route 53 to point to DR ALB                                        │
│                                                                                 │
│  RTO: 10-30 minutes                      RPO: Minutes (async replication lag) │
│  Cost: $$                                                                       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

```hcl
# Aurora Global Database
resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = "production-global"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  database_name             = "appdb"
  storage_encrypted         = true
}

# Primary cluster
resource "aws_rds_cluster" "primary" {
  provider                  = aws.primary
  cluster_identifier        = "production-primary"
  global_cluster_identifier = aws_rds_global_cluster.main.id
  engine                    = aws_rds_global_cluster.main.engine
  engine_version            = aws_rds_global_cluster.main.engine_version
  database_name             = "appdb"
  master_username           = "admin"
  master_password           = var.db_password
  
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.aurora_primary.id]
}

# Secondary cluster (pilot light)
resource "aws_rds_cluster" "secondary" {
  provider                  = aws.dr
  cluster_identifier        = "production-secondary"
  global_cluster_identifier = aws_rds_global_cluster.main.id
  engine                    = aws_rds_global_cluster.main.engine
  engine_version            = aws_rds_global_cluster.main.engine_version
  
  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = [aws_security_group.aurora_dr.id]
  
  # No master credentials - will replicate from primary
}

# DR ECS with minimal capacity
resource "aws_ecs_service" "dr" {
  provider = aws.dr
  name     = "api-dr"
  cluster  = aws_ecs_cluster.dr.id
  
  desired_count = 1  # Minimal for pilot light
  
  # Can be scaled up during failover
}
```

### Strategy 3: Warm Standby

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                             WARM STANDBY                                        │
│                                                                                 │
│  PRIMARY REGION (us-east-1)              DR REGION (us-west-2)                │
│  ┌─────────────────────────┐             ┌─────────────────────────┐          │
│  │                         │             │                         │          │
│  │  ┌───────────────────┐  │             │  ┌───────────────────┐  │          │
│  │  │   Route 53        │  │      DNS    │  │   Route 53        │  │          │
│  │  │   (Active)        │◀┼─────────────┼──│   (Passive)       │  │          │
│  │  └─────────┬─────────┘  │             │  └─────────┬─────────┘  │          │
│  │            │            │             │            │            │          │
│  │  ┌─────────▼─────────┐  │             │  ┌─────────▼─────────┐  │          │
│  │  │   ALB             │  │             │  │   ALB             │  │          │
│  │  └─────────┬─────────┘  │             │  └─────────┬─────────┘  │          │
│  │            │            │             │            │            │          │
│  │  ┌─────────▼─────────┐  │             │  ┌─────────▼─────────┐  │          │
│  │  │   ECS (10 tasks)  │  │             │  │   ECS (3 tasks)   │  │          │
│  │  └─────────┬─────────┘  │             │  │   (scaled down)   │  │          │
│  │            │            │             │  └─────────┬─────────┘  │          │
│  │  ┌─────────▼─────────┐  │   Sync      │  ┌─────────▼─────────┐  │          │
│  │  │   Aurora Primary  │──┼────────────▶│  │   Aurora Replica  │  │          │
│  │  └───────────────────┘  │   (async)   │  └───────────────────┘  │          │
│  │                         │             │                         │          │
│  │  ┌───────────────────┐  │   Sync      │  ┌───────────────────┐  │          │
│  │  │   ElastiCache     │──┼────────────▶│  │   ElastiCache     │  │          │
│  │  └───────────────────┘  │             │  └───────────────────┘  │          │
│  │                         │             │                         │          │
│  └─────────────────────────┘             └─────────────────────────┘          │
│                                                                                 │
│  On disaster:                                                                   │
│  1. Promote Aurora in DR region                                               │
│  2. Scale up ECS to production capacity (auto-scaling kicks in)              │
│  3. Route 53 health check fails → automatic DNS failover                     │
│                                                                                 │
│  RTO: 1-5 minutes                        RPO: Seconds (sync replication)      │
│  Cost: $$$                                                                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Strategy 4: Multi-Site Active/Active

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                           ACTIVE/ACTIVE                                         │
│                                                                                 │
│                         ┌───────────────────┐                                  │
│                         │    Route 53       │                                  │
│                         │  (Latency-based   │                                  │
│                         │   or Geolocation) │                                  │
│                         └─────────┬─────────┘                                  │
│                                   │                                            │
│                    ┌──────────────┴──────────────┐                            │
│                    │                             │                            │
│                    ▼                             ▼                            │
│  ┌─────────────────────────┐   ┌─────────────────────────┐                   │
│  │   REGION A (us-east-1)  │   │   REGION B (us-west-2)  │                   │
│  │                         │   │                         │                   │
│  │  ┌───────────────────┐  │   │  ┌───────────────────┐  │                   │
│  │  │  CloudFront       │  │   │  │  CloudFront       │  │                   │
│  │  └─────────┬─────────┘  │   │  └─────────┬─────────┘  │                   │
│  │            │            │   │            │            │                   │
│  │  ┌─────────▼─────────┐  │   │  ┌─────────▼─────────┐  │                   │
│  │  │  ALB + ECS (Full) │  │   │  │  ALB + ECS (Full) │  │                   │
│  │  └─────────┬─────────┘  │   │  └─────────┬─────────┘  │                   │
│  │            │            │   │            │            │                   │
│  │  ┌─────────▼─────────┐  │   │  ┌─────────▼─────────┐  │                   │
│  │  │  DynamoDB Global  │◀─┼───┼──│  DynamoDB Global  │  │                   │
│  │  │  Tables           │──┼───┼─▶│  Tables           │  │                   │
│  │  └───────────────────┘  │   │  └───────────────────┘  │                   │
│  │           Bi-directional│   │  Bi-directional        │                   │
│  │           replication   │   │  replication           │                   │
│  │                         │   │                         │                   │
│  └─────────────────────────┘   └─────────────────────────┘                   │
│                                                                                 │
│  - Both regions actively serve traffic                                         │
│  - DynamoDB Global Tables for multi-master replication                        │
│  - Route 53 distributes traffic based on latency                              │
│  - No failover needed - automatic if one region fails                         │
│                                                                                 │
│  RTO: Near-zero                          RPO: Near-zero                        │
│  Cost: $$$$                                                                     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

```hcl
# DynamoDB Global Table
resource "aws_dynamodb_table" "global" {
  name             = "user-sessions"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "user_id"
  range_key        = "session_id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  attribute {
    name = "user_id"
    type = "S"
  }
  
  attribute {
    name = "session_id"
    type = "S"
  }
  
  replica {
    region_name = "us-west-2"
  }
  
  replica {
    region_name = "eu-west-1"
  }
}

# Route 53 latency-based routing
resource "aws_route53_record" "latency_us_east" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "us-east-1"
  
  latency_routing_policy {
    region = "us-east-1"
  }
  
  alias {
    name                   = aws_lb.us_east.dns_name
    zone_id                = aws_lb.us_east.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "latency_us_west" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "us-west-2"
  
  latency_routing_policy {
    region = "us-west-2"
  }
  
  alias {
    name                   = aws_lb.us_west.dns_name
    zone_id                = aws_lb.us_west.zone_id
    evaluate_target_health = true
  }
}
```

---

## Data Replication

### RTO/RPO by Replication Type

| Service | Type | RPO | Notes |
|---------|------|-----|-------|
| **Aurora Global** | Async | < 1 second | Cross-region replication |
| **DynamoDB Global** | Async | ~ 1 second | Multi-master |
| **S3 Cross-Region** | Async | Minutes | Object-level |
| **EFS Cross-Region** | Async | Minutes | DataSync |
| **RDS Read Replica** | Async | Minutes | Cross-region |

### S3 Replication

```hcl
resource "aws_s3_bucket_replication_configuration" "dr" {
  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-all"
    status = "Enabled"
    
    filter {}  # Replicate all objects
    
    destination {
      bucket        = aws_s3_bucket.dr.arn
      storage_class = "STANDARD"
      
      # Replicate encrypted objects
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr.arn
      }
      
      # Replicate delete markers
      # Important: Set this based on requirements
    }
    
    delete_marker_replication {
      status = "Enabled"  # or "Disabled" for protection
    }
    
    # Replicate replica modifications (bi-directional)
    # Only enable if needed
  }
}

# Replication Time Control (RTC) for guaranteed SLA
resource "aws_s3_bucket_replication_configuration" "dr_rtc" {
  bucket = aws_s3_bucket.critical.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "critical-data"
    status = "Enabled"
    
    destination {
      bucket = aws_s3_bucket.critical_dr.arn
      
      # 15-minute SLA
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }
}
```

---

## Infrastructure as Code for DR

### Multi-Region Terraform Structure

```
terraform/
├── modules/
│   ├── vpc/
│   ├── ecs/
│   ├── rds/
│   └── monitoring/
├── environments/
│   ├── production/
│   │   ├── primary/           # us-east-1
│   │   │   ├── main.tf
│   │   │   ├── providers.tf
│   │   │   └── terraform.tfvars
│   │   └── dr/                # us-west-2
│   │       ├── main.tf
│   │       ├── providers.tf
│   │       └── terraform.tfvars
│   └── staging/
├── global/                    # Global resources
│   ├── route53/
│   ├── iam/
│   └── cloudfront/
└── dr-automation/
    ├── failover-lambda/
    └── runbooks/
```

### DR Module Example

```hcl
# modules/dr-infrastructure/main.tf
variable "is_dr_region" {
  description = "Whether this is the DR region"
  type        = bool
  default     = false
}

variable "capacity_mode" {
  description = "Capacity mode: full, warm, or pilot"
  type        = string
  default     = "full"
}

locals {
  capacity = {
    full  = { min = 6, max = 20, desired = 10 }
    warm  = { min = 2, max = 20, desired = 3 }
    pilot = { min = 0, max = 20, desired = 1 }
  }
}

resource "aws_ecs_service" "app" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  
  desired_count = local.capacity[var.capacity_mode].desired
  
  # Auto-scaling can increase during failover
}

resource "aws_autoscaling_group" "app" {
  name = "app-asg"
  
  min_size         = local.capacity[var.capacity_mode].min
  max_size         = local.capacity[var.capacity_mode].max
  desired_capacity = local.capacity[var.capacity_mode].desired
  
  # Scale up with SNS/Lambda during failover
}
```

---

## Testing DR

### DR Test Types

| Test Type | Frequency | Impact | Coverage |
|-----------|-----------|--------|----------|
| **Tabletop** | Quarterly | None | Process review |
| **Component** | Monthly | Low | Individual services |
| **Partial Failover** | Quarterly | Medium | Subset of traffic |
| **Full Failover** | Annually | High | Complete failover |

### Automated DR Testing

```python
# Lambda function for DR testing
import boto3
import json

route53 = boto3.client('route53')
ecs = boto3.client('ecs', region_name='us-west-2')
rds = boto3.client('rds', region_name='us-west-2')

def handler(event, context):
    test_type = event.get('test_type', 'partial')
    
    if test_type == 'component':
        return test_components()
    elif test_type == 'partial':
        return test_partial_failover()
    elif test_type == 'full':
        return test_full_failover()

def test_components():
    """Test individual DR components are healthy"""
    results = {
        'aurora_replica': check_aurora_replica(),
        'ecs_service': check_ecs_service(),
        'alb_health': check_alb_health(),
        's3_replication': check_s3_replication()
    }
    
    all_healthy = all(r['healthy'] for r in results.values())
    
    return {
        'test': 'component',
        'passed': all_healthy,
        'results': results
    }

def test_partial_failover():
    """Route 10% traffic to DR region"""
    # Update Route 53 weights
    update_route53_weights(primary=90, dr=10)
    
    # Wait and check metrics
    time.sleep(300)  # 5 minutes
    
    # Check DR region health
    dr_healthy = check_dr_region_health()
    
    # Revert
    update_route53_weights(primary=100, dr=0)
    
    return {
        'test': 'partial_failover',
        'passed': dr_healthy,
        'traffic_percentage': 10
    }

def test_full_failover():
    """Perform full DR failover (with approval)"""
    # This should require manual approval
    # Scale up DR region
    scale_dr_region('full')
    
    # Promote Aurora
    promote_aurora_replica()
    
    # Switch DNS
    update_route53_weights(primary=0, dr=100)
    
    # Verify
    time.sleep(600)  # 10 minutes
    
    return check_dr_region_health()

def check_aurora_replica():
    response = rds.describe_db_clusters(
        DBClusterIdentifier='production-secondary'
    )
    cluster = response['DBClusters'][0]
    return {
        'healthy': cluster['Status'] == 'available',
        'lag_seconds': cluster.get('ReplicationSourceIdentifier', 'N/A')
    }
```

---

## Runbooks

### Failover Runbook

```markdown
# DR Failover Runbook

## Pre-Failover Checks
- [ ] Confirm primary region is truly down (not false alarm)
- [ ] Check Aurora replication lag
- [ ] Verify DR infrastructure health
- [ ] Notify stakeholders

## Failover Steps

### Step 1: Promote Aurora in DR Region
```bash
aws rds failover-global-cluster \
  --global-cluster-identifier production-global \
  --target-db-cluster-identifier production-secondary \
  --region us-west-2
```
Expected time: 1-2 minutes

### Step 2: Scale Up DR Compute
```bash
aws ecs update-service \
  --cluster production-dr \
  --service api \
  --desired-count 10 \
  --region us-west-2
```
Expected time: 2-5 minutes

### Step 3: Update Route 53
```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789 \
  --change-batch file://failover-dns.json
```

### Step 4: Verify
- [ ] Check ALB target health
- [ ] Test API endpoints
- [ ] Monitor error rates
- [ ] Confirm data consistency

## Post-Failover
- [ ] Document timeline
- [ ] Notify customers
- [ ] Plan failback
```

---

## Interview Questions

### Q1: Design a DR strategy for an application with RTO of 15 minutes and RPO of 1 minute.

**Answer:**

**Strategy: Warm Standby**

**Architecture:**
```
Primary (us-east-1)                 DR (us-west-2)
┌───────────────────┐               ┌───────────────────┐
│ ALB + ECS (10)    │               │ ALB + ECS (2)     │
│ Aurora Primary    │──async (~1s)─▶│ Aurora Replica    │
│ ElastiCache       │               │ ElastiCache       │
└───────────────────┘               └───────────────────┘
```

**Implementation:**
1. **Aurora Global Database:** Async replication with < 1 second lag (meets 1-min RPO)
2. **Warm standby ECS:** 2 tasks always running, auto-scaling ready
3. **Route 53:** Health checks with 10-second intervals
4. **Automated failover:** Lambda triggered on health check failure

**Failover sequence (~15 min total):**
1. Health check failure detected (30 seconds)
2. Aurora promotion (1-2 minutes)
3. ECS scale-up (2-3 minutes)
4. DNS propagation (60-300 seconds)
5. Verification (5 minutes buffer)

---

### Q2: How would you handle database failover for an application that can't tolerate any data loss?

**Answer:**

**For zero data loss (RPO = 0):**

**Option 1: Aurora Global with Write Forwarding**
- Writes in DR region forwarded to primary
- If primary fails, no uncommitted transactions lost

**Option 2: Synchronous Replication**
- Not available cross-region (latency too high)
- Use Multi-AZ within region for zero RPO

**Option 3: DynamoDB Global Tables**
- Multi-master, eventual consistency
- Last-writer-wins conflict resolution
- Best for applications designed for eventual consistency

**Recommendation for critical data:**
```
Application → Write Queue (SQS) → Write to Both Regions
                                 ↓           ↓
                              Aurora     Aurora
                              Primary     DR
```
- Queue ensures writes are persisted
- Acknowledge to application after both regions confirm
- Higher latency but zero data loss
