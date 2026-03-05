# AWS Interview Scenario Questions

Real-world scenario questions for senior DevOps engineer interviews with detailed solutions.

---

## Table of Contents

1. [Architecture Design Scenarios](#architecture-design-scenarios)
2. [Troubleshooting Scenarios](#troubleshooting-scenarios)
3. [Migration Scenarios](#migration-scenarios)
4. [Cost Optimization Scenarios](#cost-optimization-scenarios)
5. [Security Scenarios](#security-scenarios)
6. [Scaling Scenarios](#scaling-scenarios)

---

## Architecture Design Scenarios

### Scenario 1: E-commerce Platform

**Question:** Design a highly available e-commerce platform that can handle Black Friday traffic (100x normal load). Requirements: < 100ms response time, 99.99% availability, global presence.

**Answer:**

```
                              ┌─────────────────┐
                              │    Route 53     │
                              │ (Latency-based) │
                              └────────┬────────┘
                                       │
                     ┌─────────────────┼─────────────────┐
                     │                 │                 │
                     ▼                 ▼                 ▼
              ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
              │ CloudFront  │   │ CloudFront  │   │ CloudFront  │
              │  (Edge)     │   │  (Edge)     │   │  (Edge)     │
              └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
                     │                 │                 │
         ┌──────────────────────────────────────────────────────┐
         │                       US Region                       │
         │  ┌─────────────────────────────────────────────────┐ │
         │  │                  VPC                             │ │
         │  │   ┌─────────┐      ┌─────────────────┐          │ │
         │  │   │   WAF   │─────▶│      ALB        │          │ │
         │  │   └─────────┘      └────────┬────────┘          │ │
         │  │                             │                    │ │
         │  │   ┌─────────────────────────┼──────────────────┐│ │
         │  │   │         ECS Fargate (Auto-scaling)         ││ │
         │  │   │   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ││ │
         │  │   │   │Task │ │Task │ │Task │ │Task │ │Task │ ││ │
         │  │   │   └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ ││ │
         │  │   └────────────────────┬───────────────────────┘│ │
         │  │                        │                         │ │
         │  │   ┌────────────────────┼────────────────────────┐│ │
         │  │   │                    │                         ││ │
         │  │   │ ┌──────────────┐   │   ┌──────────────────┐ ││ │
         │  │   │ │ ElastiCache  │◀──┴──▶│   Aurora Global  │ ││ │
         │  │   │ │   Redis      │       │   (Writer)       │ ││ │
         │  │   │ └──────────────┘       └──────────────────┘ ││ │
         │  │   └─────────────────────────────────────────────┘│ │
         │  └──────────────────────────────────────────────────┘ │
         └───────────────────────────────────────────────────────┘
```

**Key Components:**

| Component | Purpose | Config |
|-----------|---------|--------|
| **CloudFront** | Edge caching, DDoS | 24-hour TTL for static |
| **WAF** | Bot protection, rate limiting | 10,000 req/IP/5min |
| **ALB** | Layer 7 routing | Cross-zone, sticky sessions |
| **ECS Fargate** | Compute | Target tracking: 70% CPU |
| **Aurora Global** | Database | Multi-region, auto-scaling |
| **ElastiCache** | Session/product cache | Redis Cluster, 99% cache hit |

**Scaling Strategy:**
1. **Pre-scaling:** 2 weeks before, increase baseline
2. **Auto-scaling:** Target tracking on CPU and request count
3. **Aurora:** Serverless v2 for auto-scaling reads
4. **Circuit breakers:** Prevent cascade failures

---

### Scenario 2: Real-time Analytics Platform

**Question:** Design a system to process 1 million events per second from IoT devices, providing real-time dashboards and historical analysis.

**Answer:**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          REAL-TIME ANALYTICS PLATFORM                            │
│                                                                                  │
│  IoT Devices                                                                    │
│      │                                                                          │
│      ▼                                                                          │
│  ┌─────────────────┐     ┌─────────────────┐                                   │
│  │   IoT Core      │────▶│    Kinesis      │                                   │
│  │   (MQTT)        │     │  Data Streams   │                                   │
│  └─────────────────┘     │  (100 shards)   │                                   │
│                          └────────┬────────┘                                   │
│                                   │                                             │
│           ┌───────────────────────┼───────────────────────┐                    │
│           │                       │                       │                    │
│           ▼                       ▼                       ▼                    │
│  ┌─────────────────┐    ┌─────────────────┐     ┌─────────────────┐           │
│  │ Kinesis Data    │    │    Lambda       │     │   Kinesis       │           │
│  │ Firehose        │    │  (Real-time     │     │   Analytics     │           │
│  │ (to S3)         │    │   processing)   │     │   (SQL)         │           │
│  └────────┬────────┘    └────────┬────────┘     └────────┬────────┘           │
│           │                      │                       │                    │
│           ▼                      ▼                       ▼                    │
│  ┌─────────────────┐    ┌─────────────────┐     ┌─────────────────┐           │
│  │       S3        │    │   Timestream    │     │    Managed      │           │
│  │  (Data Lake)    │    │   (Real-time    │     │    Grafana      │           │
│  └────────┬────────┘    │    metrics)     │     │   (Dashboard)   │           │
│           │             └─────────────────┘     └─────────────────┘           │
│           ▼                                                                    │
│  ┌─────────────────┐                                                          │
│  │     Athena      │    Query historical data                                 │
│  │   (Ad-hoc)      │                                                          │
│  └─────────────────┘                                                          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Sizing:**
- **Kinesis:** 100 shards × 1MB/sec = 100MB/sec (1M events @ 100 bytes)
- **Lambda:** 1000 concurrent (batch process)
- **Timestream:** On-demand, auto-scales

**Cost estimate:** ~$15,000/month

---

### Scenario 3: Multi-tenant SaaS Application

**Question:** Design a multi-tenant SaaS platform where each tenant needs data isolation but shares infrastructure for cost efficiency.

**Answer:**

```
                              ┌─────────────────┐
                              │    Route 53     │
                              │  *.app.com      │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │   CloudFront    │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │   API Gateway   │
                              │  + Custom       │
                              │  Authorizer     │
                              └────────┬────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
           ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
           │   Lambda    │    │   Lambda    │    │   Lambda    │
           │  (Tenant A) │    │  (Tenant B) │    │  (Shared)   │
           └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
                  │                  │                  │
                  └──────────────────┼──────────────────┘
                                     │
      Tenant Isolation Strategy:     │
      ┌──────────────────────────────┴──────────────────────────────┐
      │                                                              │
      │  Option A: Pool Model (shared tables, tenant_id column)     │
      │  ┌────────────────────────────────────────────────────────┐ │
      │  │                    DynamoDB                             │ │
      │  │   PK: tenant_id#user_id                                │ │
      │  │   ┌────────────────────────────────────────────────┐   │ │
      │  │   │ tenant_id │ user_id │ data...                 │   │ │
      │  │   │ TENANT_A  │ user1   │ {...}                   │   │ │
      │  │   │ TENANT_B  │ user1   │ {...}                   │   │ │
      │  │   └────────────────────────────────────────────────┘   │ │
      │  └────────────────────────────────────────────────────────┘ │
      │                                                              │
      │  Option B: Silo Model (separate tables per tenant)          │
      │  ┌───────────────┐    ┌───────────────┐                    │
      │  │ Table:        │    │ Table:        │                    │
      │  │ tenantA_users │    │ tenantB_users │                    │
      │  └───────────────┘    └───────────────┘                    │
      │                                                              │
      └──────────────────────────────────────────────────────────────┘
```

**Isolation Strategies:**

| Model | Isolation | Cost | Complexity |
|-------|-----------|------|------------|
| **Pool** | Row-level (tenant_id) | Lowest | Low |
| **Bridge** | Schema per tenant | Medium | Medium |
| **Silo** | DB per tenant | Highest | High |

**Security:**
- IAM policies with tenant context
- Row-level security in database
- Separate encryption keys per tenant (optional)

---

## Troubleshooting Scenarios

### Scenario 4: Memory Leak Investigation

**Question:** Your ECS service memory usage keeps increasing until containers are killed. How would you investigate?

**Answer:**

**Step 1: Confirm the pattern**
```bash
# Check memory trends
aws cloudwatch get-metric-data \
  --metric-data-queries '[
    {
      "Id": "memory",
      "MetricStat": {
        "Metric": {
          "Namespace": "ECS/ContainerInsights",
          "MetricName": "MemoryUtilization",
          "Dimensions": [
            {"Name": "ClusterName", "Value": "production"},
            {"Name": "ServiceName", "Value": "api"}
          ]
        },
        "Period": 300,
        "Stat": "Average"
      }
    }
  ]' \
  --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

**Step 2: Get heap dump (Java example)**
```bash
# ECS Exec into container
aws ecs execute-command \
  --cluster production \
  --task $TASK_ARN \
  --container api \
  --command "/bin/sh" \
  --interactive

# Inside container
jmap -dump:format=b,file=/tmp/heap.hprof $PID
aws s3 cp /tmp/heap.hprof s3://debug-bucket/
```

**Step 3: Analyze patterns**
```bash
# Check for correlation with specific endpoints
aws logs filter-log-events \
  --log-group-name /ecs/api \
  --filter-pattern '{ $.endpoint = * }' \
  --start-time $(date -d '1 hour ago' +%s000)
```

**Step 4: Common causes:**
- Connection pool not releasing connections
- Caching without eviction
- Event listeners not removed
- Large file uploads held in memory

---

### Scenario 5: Intermittent 500 Errors

**Question:** Users report random 500 errors, but they can't reproduce consistently. How do you investigate?

**Answer:**

**Investigation workflow:**

```
1. Quantify the problem
   ├─▶ Error rate? (0.1%, 1%, 10%?)
   ├─▶ Affected endpoints?
   └─▶ Time pattern?

2. Correlate with events
   ├─▶ Deployments?
   ├─▶ Traffic spikes?
   └─▶ Dependency issues?

3. Analyze logs
   ├─▶ Error messages
   ├─▶ Stack traces
   └─▶ Request context

4. Check dependencies
   ├─▶ Database errors
   ├─▶ Cache timeouts
   └─▶ External API failures
```

**Commands:**

```bash
# 1. Get error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=app/api/xxx \
  --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Sum

# 2. Find error patterns
aws logs start-query \
  --log-group-name /ecs/api \
  --start-time $(date -d '24 hours ago' +%s) \
  --end-time $(date +%s) \
  --query-string '
    filter @message like /ERROR|Exception|500/
    | parse @message "endpoint=* " as endpoint
    | stats count() as errors by endpoint, bin(1h)
    | sort errors desc
  '

# 3. Check for race conditions or timing issues
aws logs filter-log-events \
  --log-group-name /ecs/api \
  --filter-pattern '"500" "timeout"'
```

**Common causes of intermittent 500s:**
1. **Race conditions:** Add distributed locking
2. **Connection pool exhaustion:** Increase pool size, add retry
3. **Timeouts:** Increase timeouts, add circuit breaker
4. **Memory pressure:** Scale or optimize

---

## Migration Scenarios

### Scenario 6: Monolith to Microservices

**Question:** How would you migrate a monolithic application to microservices on AWS with zero downtime?

**Answer:**

**Strangler Fig Pattern:**

```
Phase 1: Baseline
┌──────────────────────────────────────────────────┐
│                    MONOLITH                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐         │
│  │  Users   │ │  Orders  │ │ Payments │         │
│  └──────────┘ └──────────┘ └──────────┘         │
│                    │                             │
│             ┌──────▼──────┐                      │
│             │  Monolith   │                      │
│             │     DB      │                      │
│             └─────────────┘                      │
└──────────────────────────────────────────────────┘

Phase 2: Extract first service
┌──────────────────────────────────────────────────┐
│         ┌─────────────┐                          │
│         │   API GW    │ (routes /users to new)  │
│         └──────┬──────┘                          │
│                │                                 │
│     ┌──────────┼──────────┐                     │
│     │          │          │                     │
│     ▼          ▼          ▼                     │
│ ┌────────┐ ┌────────┐ ┌────────┐               │
│ │ Users  │ │Monolith│ │Monolith│               │
│ │(new μs)│ │(Orders)│ │(Paymts)│               │
│ └───┬────┘ └───┬────┘ └───┬────┘               │
│     │          │          │                     │
│ ┌───▼───┐  ┌───▼──────────▼───┐                │
│ │ Users │  │    Monolith      │                │
│ │  DB   │  │       DB         │                │
│ └───────┘  └──────────────────┘                │
└──────────────────────────────────────────────────┘

Phase 3: All services extracted
┌──────────────────────────────────────────────────┐
│         ┌─────────────┐                          │
│         │   API GW    │                          │
│         └──────┬──────┘                          │
│                │                                 │
│     ┌──────────┼──────────┐                     │
│     │          │          │                     │
│     ▼          ▼          ▼                     │
│ ┌────────┐ ┌────────┐ ┌────────┐               │
│ │ Users  │ │ Orders │ │Payments│               │
│ │   μs   │ │   μs   │ │   μs   │               │
│ └───┬────┘ └───┬────┘ └───┬────┘               │
│     │          │          │                     │
│ ┌───▼───┐  ┌───▼───┐  ┌───▼───┐                │
│ │ Users │  │ Orders│  │Payments│               │
│ │  DB   │  │  DB   │  │   DB  │                │
│ └───────┘  └───────┘  └───────┘                │
└──────────────────────────────────────────────────┘
```

**Implementation Steps:**

1. **Add API Gateway in front of monolith**
2. **Extract one service at a time:**
   - Start with least-coupled domain
   - Dual-write during transition
   - Use feature flags for routing
3. **Data migration:**
   - CDC (Change Data Capture) for sync
   - Verify data consistency
4. **Cutover:**
   - Shadow traffic testing
   - Gradual traffic shift
   - Rollback plan

---

## Cost Optimization Scenarios

### Scenario 7: $50K/month AWS Bill Optimization

**Question:** Your AWS bill is $50,000/month and leadership wants 30% reduction. What's your approach?

**Answer:**

**Analysis Framework:**

```
Cost Breakdown (typical):
├── EC2/ECS Compute: 40% ($20,000)
├── RDS/Database: 25% ($12,500)
├── Data Transfer: 15% ($7,500)
├── Storage (S3/EBS): 10% ($5,000)
└── Other: 10% ($5,000)

Target: Save $15,000/month
```

**Quick Wins:**

| Area | Action | Savings |
|------|--------|---------|
| **Compute** | Savings Plans (3yr) | 40% = $8,000 |
| **Compute** | Right-size instances | 15% = $3,000 |
| **RDS** | Reserved Instances | 30% = $3,750 |
| **Storage** | S3 lifecycle policies | 50% = $2,500 |

**Implementation:**

```hcl
# 1. Savings Plans (commit to $14K compute/month)
# Saves 40% = $8K

# 2. Right-sizing
resource "aws_instance" "api" {
  instance_type = "m5.large"  # Was m5.xlarge
}

# 3. Spot Instances for non-critical
resource "aws_autoscaling_group" "workers" {
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 2
      on_demand_percentage_above_base_capacity = 20
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
  }
}

# 4. S3 Lifecycle
resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.logs.id
  
  rule {
    id     = "archive-old-logs"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 365
    }
  }
}
```

---

## Security Scenarios

### Scenario 8: Security Breach Response

**Question:** CloudTrail shows suspicious API calls from an IAM user at 3 AM. What are your immediate steps?

**Answer:**

**Incident Response Timeline:**

```
T+0: Alert triggered
  │
T+5min: Contain
  ├─▶ Disable IAM user credentials
  ├─▶ Check active sessions (STS)
  └─▶ Review security groups
  │
T+15min: Assess scope
  ├─▶ CloudTrail analysis
  ├─▶ Affected resources
  └─▶ Data exfiltration check
  │
T+1hr: Investigate
  ├─▶ How credentials were compromised
  ├─▶ Full attack timeline
  └─▶ Other affected accounts
  │
T+4hr: Remediate
  ├─▶ Rotate all credentials
  ├─▶ Patch vulnerabilities
  └─▶ Strengthen controls
  │
T+24hr: Document
  ├─▶ Incident report
  └─▶ Lessons learned
```

**Immediate Commands:**

```bash
# 1. Disable the user
aws iam update-login-profile --user-name compromised-user --password-reset-required
aws iam list-access-keys --user-name compromised-user
aws iam update-access-key --user-name compromised-user --access-key-id AKIA... --status Inactive

# 2. Revoke all sessions
aws iam put-user-policy --user-name compromised-user --policy-name DenyAll --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Action": "*",
    "Resource": "*"
  }]
}'

# 3. Analyze CloudTrail
aws logs filter-log-events \
  --log-group-name CloudTrail/logs \
  --filter-pattern '{ $.userIdentity.userName = "compromised-user" }' \
  --start-time $(date -d '24 hours ago' +%s000)

# 4. Check for persistence (new IAM users, roles)
aws iam list-users --query 'Users[?CreateDate>=`2024-01-15`]'
aws iam list-roles --query 'Roles[?CreateDate>=`2024-01-15`]'
```

---

## Scaling Scenarios

### Scenario 9: Sudden Traffic Spike

**Question:** Your application receives 10x normal traffic unexpectedly. Current setup can't handle it. What do you do?

**Answer:**

**Immediate actions (0-5 min):**

```bash
# 1. Scale ECS immediately
aws ecs update-service \
  --cluster production \
  --service api \
  --desired-count 50  # 5x current

# 2. Enable CloudFront caching for cacheable endpoints
# (if not already)

# 3. Scale Aurora read replicas
aws rds create-db-instance \
  --db-instance-identifier read-replica-emergency \
  --source-db-instance-identifier production \
  --db-instance-class db.r5.2xlarge
```

**Short-term (5-30 min):**

```bash
# 1. Increase auto-scaling maximums
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/production/api \
  --scalable-dimension ecs:service:DesiredCount \
  --max-capacity 200

# 2. Enable rate limiting to protect backend
# WAF rate-based rule

# 3. Scale Redis cluster
# Add nodes or switch to larger instance
```

**Communication:**
- Status page update
- Internal Slack alert
- Customer notification if needed

**Post-incident:**
- Review scaling policies
- Add predictive scaling
- Load test for similar scenarios

---

### Scenario 10: Database Connection Exhaustion

**Question:** Your application starts throwing "too many connections" errors to RDS during peak traffic. How do you solve this short-term and long-term?

**Answer:**

**Immediate fix:**

```bash
# 1. Kill idle connections (careful!)
# Connect to DB and run:
# SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND query_start < now() - interval '5 minutes';

# 2. Increase max_connections (requires reboot for some params)
aws rds modify-db-instance \
  --db-instance-identifier production \
  --db-parameter-group-name high-connections
```

**Short-term (same day):**

```hcl
# RDS Proxy for connection pooling
resource "aws_db_proxy" "main" {
  name                   = "api-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.private_subnet_ids
  
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db.arn
    iam_auth    = "DISABLED"
  }
}
```

**Long-term:**

1. **Application-level pooling:** PgBouncer, connection pool in app
2. **Read replicas:** Route read traffic separately
3. **Caching:** ElastiCache for frequently accessed data
4. **Architecture review:** Consider if DB is the right choice for all queries

**Connection management best practices:**

```python
# Python example with proper connection handling
import psycopg2
from contextlib import contextmanager
from psycopg2 import pool

# Create a connection pool
connection_pool = psycopg2.pool.ThreadedConnectionPool(
    minconn=5,
    maxconn=20,  # Per instance, multiply by instance count
    host=os.environ['DB_HOST'],
    database='app',
    user=os.environ['DB_USER'],
    password=os.environ['DB_PASSWORD']
)

@contextmanager
def get_connection():
    conn = connection_pool.getconn()
    try:
        yield conn
        conn.commit()
    except:
        conn.rollback()
        raise
    finally:
        connection_pool.putconn(conn)

# Usage
with get_connection() as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

---

## Summary: Key Interview Points

### Architecture
- Always design for failure
- Multi-AZ by default
- Use managed services when possible
- Design stateless applications

### Troubleshooting
- Use CloudWatch, X-Ray, CloudTrail
- Systematic approach (OODA loop)
- Always check recent changes first
- Have runbooks ready

### Security
- Least privilege always
- Encrypt everything
- Have incident response plan
- Regular security audits

### Cost
- Right-size continuously
- Use Savings Plans/Reserved Instances
- Monitor with Cost Explorer
- Set billing alerts

### Scaling
- Design for 10x from day one
- Use auto-scaling everywhere
- Cache aggressively
- Test with load testing
