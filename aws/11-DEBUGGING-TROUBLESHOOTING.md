# AWS Debugging and Troubleshooting Guide

Practical troubleshooting techniques for production AWS environments.

---

## Table of Contents

1. [Debugging Framework](#debugging-framework)
2. [Network Troubleshooting](#network-troubleshooting)
3. [ECS Troubleshooting](#ecs-troubleshooting)
4. [Lambda Troubleshooting](#lambda-troubleshooting)
5. [Database Troubleshooting](#database-troubleshooting)
6. [Load Balancer Issues](#load-balancer-issues)
7. [IAM Permission Issues](#iam-permission-issues)
8. [Performance Troubleshooting](#performance-troubleshooting)
9. [Useful CLI Commands](#useful-cli-commands)
10. [Interview Questions](#interview-questions)

---

## Debugging Framework

### The OODA Loop for Incidents

```
┌────────────────────────────────────────────────────────────────────────┐
│                        OODA LOOP FOR INCIDENTS                         │
│                                                                        │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐    │
│   │ OBSERVE  │────▶│  ORIENT  │────▶│  DECIDE  │────▶│   ACT    │    │
│   └──────────┘     └──────────┘     └──────────┘     └──────────┘    │
│        │                │                │                │           │
│        ▼                ▼                ▼                ▼           │
│   - Metrics         - What changed?  - Quick fix     - Implement     │
│   - Logs            - Error msgs     - Rollback      - Monitor       │
│   - Alarms          - Scope impact   - Scale up      - Document      │
│   - X-Ray traces    - Correlate      - Failover                      │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Systematic Approach

```
1. ASSESS IMPACT
   └─▶ Who is affected?
   └─▶ What is broken?
   └─▶ When did it start?

2. CHECK RECENT CHANGES
   └─▶ Deployments
   └─▶ Config changes
   └─▶ Infrastructure changes

3. REVIEW METRICS/LOGS
   └─▶ CloudWatch metrics
   └─▶ Application logs
   └─▶ AWS service logs (CloudTrail)

4. ISOLATE THE PROBLEM
   └─▶ Network?
   └─▶ Application?
   └─▶ Database?
   └─▶ Permissions?

5. FIX OR MITIGATE
   └─▶ Rollback
   └─▶ Scale
   └─▶ Failover
   └─▶ Hotfix
```

---

## Network Troubleshooting

### Common Issues and Solutions

| Symptom | Possible Causes | Diagnosis |
|---------|----------------|-----------|
| **Connection timeout** | Security group, NACL, route table | VPC Flow Logs, Reachability Analyzer |
| **Connection refused** | Service not running, wrong port | telnet, ELB health checks |
| **Intermittent failures** | Health check failures, scaling | ALB access logs, target health |
| **DNS resolution fails** | VPC DNS settings, Route 53 | dig, nslookup, DNS logs |

### VPC Flow Logs Analysis

```bash
# Enable flow logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-12345678 \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name vpc-flow-logs

# CloudWatch Insights query for rejected traffic
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 100
```

### Security Group Debugging

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-12345678 \
  --query 'SecurityGroups[0].IpPermissions'

# Check which ENIs use this security group
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=sg-12345678" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Description]'
```

### VPC Reachability Analyzer

```hcl
# Create reachability analysis
resource "aws_ec2_network_insights_path" "test" {
  source      = aws_instance.source.id
  destination = aws_instance.destination.id
  protocol    = "tcp"
  
  destination_port = 443
}

resource "aws_ec2_network_insights_analysis" "test" {
  network_insights_path_id = aws_ec2_network_insights_path.test.id
}
```

### Common Network Fixes

```bash
# Fix: Security group missing rule
aws ec2 authorize-security-group-ingress \
  --group-id sg-12345678 \
  --protocol tcp \
  --port 443 \
  --source-group sg-87654321

# Fix: NACL blocking traffic
aws ec2 create-network-acl-entry \
  --network-acl-id acl-12345678 \
  --ingress \
  --rule-number 100 \
  --protocol tcp \
  --port-range From=443,To=443 \
  --cidr-block 10.0.0.0/16 \
  --rule-action allow
```

---

## ECS Troubleshooting

### Task Failure Reasons

| Error | Cause | Solution |
|-------|-------|----------|
| **RESOURCE:MEMORY** | Task requested more memory than available | Increase task memory or instance size |
| **RESOURCE:CPU** | CPU reservation exceeded | Adjust CPU units or scale cluster |
| **AGENT** | ECS agent disconnected | Check EC2 instance health |
| **CannotPullContainer** | ECR permissions or image doesn't exist | Fix IAM role or image tag |
| **CannotStartContainer** | Container crashed on start | Check container logs |

### Debugging Commands

```bash
# Check task status
aws ecs describe-tasks \
  --cluster production \
  --tasks arn:aws:ecs:us-east-1:123456789:task/xxx \
  --query 'tasks[0].{status:lastStatus,reason:stoppedReason,containers:containers[*].{name:name,exitCode:exitCode,reason:reason}}'

# Check service events (last 100)
aws ecs describe-services \
  --cluster production \
  --services api-service \
  --query 'services[0].events[:10]'

# Get container logs (most recent)
aws logs tail /ecs/api-service --follow

# Check if image exists
aws ecr describe-images \
  --repository-name api \
  --image-ids imageTag=latest

# Check task definition
aws ecs describe-task-definition \
  --task-definition api:123 \
  --query 'taskDefinition.containerDefinitions[*].{name:name,image:image,memory:memory,cpu:cpu}'
```

### ECS Exec for Debugging

```bash
# Enable ECS Exec on service
aws ecs update-service \
  --cluster production \
  --service api-service \
  --enable-execute-command

# Connect to running container
aws ecs execute-command \
  --cluster production \
  --task arn:aws:ecs:us-east-1:123456789:task/xxx \
  --container api \
  --interactive \
  --command "/bin/bash"

# Inside container, debug
curl localhost:8080/health
cat /var/log/app.log
env | grep DATABASE
```

### Common ECS Issues and Fixes

```bash
# Issue: Task stuck in PENDING
# Cause: No capacity in cluster
# Fix: Check capacity provider
aws ecs describe-capacity-providers \
  --capacity-providers $(aws ecs describe-clusters --clusters production \
    --query 'clusters[0].capacityProviders' --output text)

# Issue: Service stuck in deployment
# Cause: Health checks failing
# Fix: Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Issue: Container restarting
# Cause: OOM or crash
# Fix: Check logs and increase memory
aws logs filter-log-events \
  --log-group-name /ecs/api-service \
  --filter-pattern "OutOfMemory OR OOM OR killed"
```

---

## Lambda Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| **Task timed out** | Execution exceeded timeout | Increase timeout or optimize code |
| **Module not found** | Missing dependency | Check layer or deployment package |
| **Permission denied** | IAM role missing permission | Add required IAM permissions |
| **ENI limit** | VPC Lambda ENI quota | Request quota increase |
| **Memory exceeded** | Out of memory | Increase memory allocation |

### Debugging Commands

```bash
# Get function configuration
aws lambda get-function-configuration \
  --function-name my-function \
  --query '{memory:MemorySize,timeout:Timeout,runtime:Runtime,role:Role}'

# Get recent invocations
aws logs filter-log-events \
  --log-group-name /aws/lambda/my-function \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"

# Check concurrent executions
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ConcurrentExecutions \
  --dimensions Name=FunctionName,Value=my-function \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum

# Test function manually
aws lambda invoke \
  --function-name my-function \
  --payload '{"key": "value"}' \
  --log-type Tail \
  response.json 2>&1 | jq -r '.LogResult' | base64 -d
```

### Cold Start Analysis

```python
# Add cold start logging to Lambda
import time
COLD_START = True

def handler(event, context):
    global COLD_START
    
    if COLD_START:
        print(f"COLD START - Init duration: {context.get_remaining_time_in_millis()}ms remaining")
        COLD_START = False
    
    start = time.time()
    # ... function logic ...
    duration = (time.time() - start) * 1000
    
    print(f"Execution duration: {duration:.2f}ms")
    return {"statusCode": 200}
```

---

## Database Troubleshooting

### RDS/Aurora Issues

| Symptom | Cause | Diagnosis | Solution |
|---------|-------|-----------|----------|
| **Connection refused** | Security group | VPC Flow Logs | Fix SG rules |
| **Too many connections** | Connection leak | RDS metrics | Connection pooling |
| **High CPU** | Bad queries | Performance Insights | Optimize queries |
| **High latency** | Disk I/O | IOPS metrics | Upgrade to io2 |
| **Replication lag** | Write-heavy | Replica lag metric | Scale replica |

### Performance Insights Queries

```sql
-- Find slow queries (from Performance Insights)
-- Available in RDS Console → Performance Insights

-- Or use CloudWatch Logs Insights for slow query log:
fields @timestamp, @message
| filter @message like /Query/
| parse @message "Query_time: * Lock_time: * Rows_sent: * Rows_examined: *" as query_time, lock_time, rows_sent, rows_examined
| filter query_time > 1
| sort query_time desc
| limit 20
```

### RDS Commands

```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier production \
  --query 'DBInstances[0].{status:DBInstanceStatus,cpu:PendingModifiedValues,storage:AllocatedStorage}'

# Check connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=production \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum

# Force failover (for testing)
aws rds reboot-db-instance \
  --db-instance-identifier production \
  --force-failover
```

### DynamoDB Issues

```bash
# Check consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=my-table \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum

# Check for throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=my-table \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum
```

---

## Load Balancer Issues

### ALB Troubleshooting

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123:targetgroup/api/xxx

# Get ALB access logs (from S3)
aws s3 cp s3://alb-logs/AWSLogs/123456789/elasticloadbalancing/us-east-1/2024/01/15/ . --recursive

# Parse logs for 5xx errors
zcat *.log.gz | awk '$9 ~ /^5/ { print $13, $9, $14, $15 }' | head -20

# Check listener rules
aws elbv2 describe-rules \
  --listener-arn arn:aws:elasticloadbalancing:us-east-1:123:listener/app/xxx/yyy

# Check ALB attributes
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:123:loadbalancer/app/xxx
```

### Common ALB Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| **504 Gateway Timeout** | Target not responding in time | Increase idle timeout, check target |
| **502 Bad Gateway** | Target returning invalid response | Check application logs |
| **503 Service Unavailable** | No healthy targets | Check health checks |
| **Fixed 100% CPU** | SSL negotiation issues | Check certificates |

---

## IAM Permission Issues

### Debugging Steps

```bash
# 1. Check who you are
aws sts get-caller-identity

# 2. Simulate policy
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789:role/my-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/mykey

# 3. Check role policies
aws iam list-attached-role-policies --role-name my-role
aws iam list-role-policies --role-name my-role

# 4. Get inline policy
aws iam get-role-policy \
  --role-name my-role \
  --policy-name my-inline-policy

# 5. Check CloudTrail for access denied
aws logs filter-log-events \
  --log-group-name CloudTrail/logs \
  --filter-pattern "AccessDenied"
```

### Common IAM Fixes

```hcl
# Missing permission example
resource "aws_iam_role_policy_attachment" "fix" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Custom policy for specific resource
resource "aws_iam_role_policy" "custom" {
  name = "s3-access"
  role = aws_iam_role.ecs_task.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::my-bucket/*"
      }
    ]
  })
}
```

---

## Performance Troubleshooting

### Identifying Bottlenecks

```
Application slow?
       │
       ├─▶ High latency in ALB? ──▶ Target issue
       │
       ├─▶ High latency in app? ──▶ Application profiling
       │
       ├─▶ High DB latency? ──▶ Query optimization
       │
       └─▶ Network latency? ──▶ VPC/region issue

Use X-Ray to trace the full request path
```

### X-Ray Analysis

```bash
# Get service map
aws xray get-service-graph \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s)

# Get traces with high latency
aws xray get-trace-summaries \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression 'responsetime > 5'

# Get trace details
aws xray batch-get-traces \
  --trace-ids 1-xxxxx-yyyyy
```

---

## Useful CLI Commands

```bash
# Quick health check suite
alias aws-health='
echo "=== ECS Services ===" && \
aws ecs list-services --cluster production --query "serviceArns" && \
echo "=== ALB Targets ===" && \
aws elbv2 describe-target-health --target-group-arn $TG_ARN && \
echo "=== Recent Alarms ===" && \
aws cloudwatch describe-alarms --state-value ALARM --query "MetricAlarms[*].AlarmName"
'

# Get all errors in last hour
aws logs filter-log-events \
  --log-group-name /ecs/api \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR" \
  --query 'events[*].message' \
  --output text

# Check recent deployments
aws ecs describe-services \
  --cluster production \
  --services api \
  --query 'services[0].deployments[*].{status:status,running:runningCount,desired:desiredCount,created:createdAt}'

# Find Lambda errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/my-function \
  --filter-pattern "?ERROR ?Exception ?Traceback" \
  --start-time $(date -d '1 hour ago' +%s000)
```

---

## Interview Questions

### Q1: Users report intermittent 504 errors. How would you debug this?

**Answer:**

**Step 1: Confirm the issue**
```bash
# Check ALB metrics for 504s
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_ELB_504_Count \
  --dimensions Name=LoadBalancer,Value=app/my-alb/xxx \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum
```

**Step 2: Check target health**
```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...
```

**Step 3: Analyze access logs**
- Look for requests timing out
- Check which targets are returning errors
- Check response time patterns

**Step 4: Common causes:**
1. **Target timeout:** Increase ALB idle timeout
2. **Target overloaded:** Scale up, check CPU/memory
3. **Database blocking:** Check connection pool, slow queries
4. **Network issue:** VPC flow logs, security groups

---

### Q2: ECS service keeps restarting. What's your approach?

**Answer:**

**Immediate check:**
```bash
# Get stopped reason
aws ecs describe-tasks --cluster production --tasks $(aws ecs list-tasks --cluster production --service-name api --desired-status STOPPED --query 'taskArns[0]' --output text) --query 'tasks[0].stoppedReason'
```

**Common causes and fixes:**

1. **Health check failure:**
   - Verify health check endpoint works
   - Check grace period is enough
   - Check target group health

2. **OOM (OutOfMemory):**
   - Check memory metrics
   - Increase task memory
   - Fix memory leak

3. **Container crash:**
   - Check container logs
   - ECS Exec into container
   - Test locally

4. **Image pull failure:**
   - Verify image exists
   - Check ECR permissions
   - Check task execution role

**Debug with ECS Exec:**
```bash
aws ecs execute-command --cluster production --task xxx --container api --command "/bin/sh" --interactive
```
