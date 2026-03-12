# AWS Compliance Scanner B — Step Functions Orchestration

> **Approach B**: Request → FastAPI → Step Functions → Lambda Functions  
> Step Functions handles orchestration, routing, retries, and error handling.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    AWS COMPLIANCE SCANNER B — STEP FUNCTIONS                         │
│                                                                                      │
│   CLIENT                                                                             │
│     │                                                                                │
│     ▼                                                                                │
│  ┌──────────────────────────────────────────────────────────────────────┐           │
│  │              AWS EKS CLUSTER (us-east-1)                              │           │
│  │                                                                       │           │
│  │  ┌─────────────────┐                                                 │           │
│  │  │  Istio Ingress  │◀── HTTPS (ACM TLS)                              │           │
│  │  │    Gateway       │                                                 │           │
│  │  └────────┬────────┘                                                 │           │
│  │           │                                                           │           │
│  │  ┌────────▼────────┐                                                 │           │
│  │  │    FastAPI      │  ← Minimal: validates, creates job, starts SFN │           │
│  │  │  (thin layer)   │                                                 │           │
│  │  └────────┬────────┘                                                 │           │
│  │           │                                                           │           │
│  └───────────┼───────────────────────────────────────────────────────────┘          │
│              │                                                                       │
│              │  sfn.start_execution(stateMachineArn, input)                         │
│              ▼                                                                       │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                    AWS STEP FUNCTIONS (Express Workflow)                       │  │
│  │                                                                                │  │
│  │  ┌─────────────────┐                                                          │  │
│  │  │ PrepareCheckTasks│  Update DynamoDB: status=RUNNING                        │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │  FanOutByAccount │  Map state: MaxConcurrency=10                           │  │
│  │  │      (Map)       │                                                          │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │  FanOutByRegion │  Nested Map: MaxConcurrency=5                            │  │
│  │  │      (Map)       │                                                          │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │  FanOutByCheck  │  Nested Map: MaxConcurrency=15                           │  │
│  │  │      (Map)       │                                                          │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────────────────────────────────────────────────────────┐      │  │
│  │  │                      CHOICE STATE: RouteToCheck                      │      │  │
│  │  │                                                                      │      │  │
│  │  │   check_id == "cfn_drift"      → InvokeCfnDriftCheck                │      │  │
│  │  │   check_id == "vpc_flow_logs"  → InvokeVpcFlowLogsCheck             │      │  │
│  │  │   check_id == "s3_encryption"  → InvokeS3EncryptionCheck            │      │  │
│  │  │   check_id == "iam_mfa_root"   → InvokeIamMfaCheck                  │      │  │
│  │  │   check_id == "sg_unrestricted"→ InvokeSgUnrestrictedSshCheck       │      │  │
│  │  │   ...                          → ...                                 │      │  │
│  │  │   default                      → UnknownCheckHandler                 │      │  │
│  │  │                                                                      │      │  │
│  │  └────────┬─────────────────────────────────────────────────────────────┘      │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │  Lambda Invoke  │  Built-in retry: 3 attempts, exponential backoff         │  │
│  │  │  (per check)    │  Catch: States.ALL → HandleCheckError                    │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │ AggregateResults│  Lambda: flattens nested results, writes to DynamoDB    │  │
│  │  └────────┬────────┘                                                          │  │
│  │           │                                                                    │  │
│  │  ┌────────▼────────┐                                                          │  │
│  │  │UpdateJobComplete│  DynamoDB: status=COMPLETED, passed/failed/errors        │  │
│  │  └─────────────────┘                                                          │  │
│  │                                                                                │  │
│  └────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                       │
│  ┌────────────────────────────────────────────────────────────────────────────────┐  │
│  │                    AWS LAMBDA (compliance-check-*)                               │  │
│  │                                                                                  │  │
│  │  cfn-drift  │  vpc-flow-logs  │  s3-encryption │  iam-mfa    │  cloudtrail     │  │
│  │  sg-ssh     │  guardduty      │  rds-encryption│  ebs-encrypt│  config-recorder│  │
│  │  ...                                                                             │  │
│  └────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Approach Comparison: A vs B

### High-Level Summary

| Aspect | **Approach A** (Direct Lambda) | **Approach B** (Step Functions) |
|--------|-------------------------------|--------------------------------|
| **Orchestration** | FastAPI + asyncio + ThreadPool | AWS Step Functions |
| **Concurrency Control** | Python Semaphore | Map state MaxConcurrency |
| **Retry Logic** | Manual in Python | Built-in (Retry block) |
| **Error Handling** | try/except in invoker | Catch states + error paths |
| **Routing** | Function name string | Choice state |
| **Visibility** | CloudWatch Logs + OTEL | Step Functions Console + X-Ray |
| **State Persistence** | In-memory during execution | Automatic (execution history) |
| **Cost Model** | Lambda invocations only | Lambda + Step Functions state transitions |

---

### Detailed Comparison

#### 1. **Architecture Complexity**

```
APPROACH A (Direct Lambda):
┌─────────────┐     ┌─────────────────────────────────────────┐
│   FastAPI   │────▶│  lambda_invoker.py                     │
│             │     │  - asyncio.Semaphore(20)                │
│             │     │  - ThreadPoolExecutor                   │
│             │     │  - asyncio.gather(*invocations)         │
│             │     │  - Manual trace context propagation     │
│             │     │  - Manual error aggregation             │
└─────────────┘     └─────────────────────────────────────────┘

APPROACH B (Step Functions):
┌─────────────┐     ┌──────────────────┐     ┌───────────────┐
│   FastAPI   │────▶│  Step Functions  │────▶│    Lambda     │
│  (thin)     │     │  (orchestrator)  │     │   (checks)    │
└─────────────┘     └──────────────────┘     └───────────────┘
```

- **Approach A**: FastAPI code handles orchestration complexity (~180 lines)
- **Approach B**: FastAPI is thin (~50 lines); Step Functions handles orchestration

#### 2. **Concurrency Control**

**Approach A:**
```python
semaphore = asyncio.Semaphore(settings.MAX_CONCURRENT_LAMBDA_CALLS)  # 20

async def bounded_invoke(check, account_id, region):
    async with semaphore:
        return await loop.run_in_executor(None, _invoke_lambda, ...)
```

**Approach B:**
```json
{
  "Type": "Map",
  "MaxConcurrency": 10,  // Per account
  "Iterator": {
    "States": {
      "FanOutByRegion": {
        "Type": "Map",
        "MaxConcurrency": 5,  // Per region
        "Iterator": {
          "States": {
            "FanOutByCheck": {
              "Type": "Map",
              "MaxConcurrency": 15  // Per check
            }
          }
        }
      }
    }
  }
}
```

- **Approach A**: Single flat concurrency limit (20 total)
- **Approach B**: Hierarchical concurrency (10 accounts × 5 regions × 15 checks = 750 max)
- **Winner**: **Approach B** — more granular control, prevents account/region hotspots

#### 3. **Retry Logic**

**Approach A:**
```python
# Manual retry in _invoke_lambda or wrapper
for attempt in range(MAX_RETRIES):
    try:
        response = client.invoke(...)
        break
    except TooManyRequestsException:
        time.sleep(2 ** attempt)
```

**Approach B:**
```json
{
  "Retry": [{
    "ErrorEquals": ["Lambda.TooManyRequestsException", "Lambda.ServiceException"],
    "IntervalSeconds": 2,
    "MaxAttempts": 3,
    "BackoffRate": 2.0
  }]
}
```

- **Approach A**: Must implement retry logic in application code
- **Approach B**: Declarative retry configuration, handled by Step Functions
- **Winner**: **Approach B** — cleaner, less code, battle-tested

#### 4. **Error Handling & Partial Failure**

**Approach A:**
```python
try:
    results = await asyncio.gather(*tasks, return_exceptions=False)
except Exception:
    # One failure fails the entire gather (unless return_exceptions=True)
    # Must manually track partial results
```

**Approach B:**
```json
{
  "Catch": [{
    "ErrorEquals": ["States.ALL"],
    "ResultPath": "$.error",
    "Next": "HandleCheckError"
  }]
}
// Each check can fail independently; others continue
// Errors captured in result structure
```

- **Approach A**: Harder to handle partial failures gracefully
- **Approach B**: Each check is independent; errors don't cascade
- **Winner**: **Approach B** — better fault isolation

#### 5. **Lambda Routing (Choice Logic)**

**Approach A:**
```python
function_name = f"{settings.LAMBDA_FUNCTION_PREFIX}-{check['id']}"
# String interpolation - no sophisticated routing
# Adding new check = add to REGISTERED_CHECKS list
```

**Approach B:**
```json
{
  "Type": "Choice",
  "Choices": [
    {
      "Variable": "$.check_id",
      "StringEquals": "cfn_drift",
      "Next": "InvokeCfnDriftCheck"
    },
    {
      "Variable": "$.check_id",
      "StringEquals": "vpc_flow_logs",
      "Next": "InvokeVpcFlowLogsCheck"
    }
  ],
  "Default": "UnknownCheckHandler"
}
```

- **Approach A**: Simpler string-based routing
- **Approach B**: More verbose but enables complex routing (e.g., conditional checks)
- **Trade-off**: Approach B is more flexible but requires Terraform/JSON updates

#### 6. **Observability**

| Feature | Approach A | Approach B |
|---------|-----------|-----------|
| **Execution Graph** | Manual OTEL spans | Built-in Step Functions Console |
| **State History** | CloudWatch Logs | Execution history with inputs/outputs |
| **Debugging** | grep CloudWatch | Visual workflow + click-through |
| **X-Ray Integration** | Manual instrumentation | Native tracing_configuration |
| **Cost Attribution** | Manual tagging | Automatic per-execution metrics |

- **Winner**: **Approach B** — better out-of-the-box observability

#### 7. **Cost Analysis**

**Approach A (Lambda-only):**
```
Cost = Lambda invocations × (duration × memory cost)

Example: 50 accounts × 5 regions × 15 checks = 3,750 Lambda invocations
At 300ms avg, 256MB: ~$0.08 per full scan
```

**Approach B (Step Functions + Lambda):**
```
Cost = Lambda invocations + Step Functions state transitions

State transitions:
- PrepareCheckTasks: 1
- FanOutByAccount: 50 accounts
- FanOutByRegion: 50 × 5 = 250
- FanOutByCheck: 250 × 15 = 3,750
- Choice (RouteToCheck): 3,750
- Lambda invoke: 3,750
- AggregateResults: 1
- UpdateJobComplete: 1

Total transitions: ~11,250 per scan
Express Workflow: $0.000001 per transition = $0.01125 per scan

Lambda costs: same as Approach A = ~$0.08
Total: ~$0.09 per scan
```

| Scan Size | Approach A | Approach B | Difference |
|-----------|-----------|-----------|------------|
| Small (1 account, 1 region, 15 checks) | $0.001 | $0.002 | +$0.001 |
| Medium (10 accounts, 3 regions, 15 checks) | $0.016 | $0.021 | +$0.005 |
| Large (50 accounts, 5 regions, 15 checks) | $0.08 | $0.09 | +$0.01 |
| Enterprise (100 accounts, 10 regions, 15 checks) | $0.32 | $0.36 | +$0.04 |

- **Winner**: **Approach A** — ~10-15% cheaper (but difference is small)

#### 8. **Scalability**

**Approach A:**
- Limited by FastAPI pod memory (must hold all concurrent futures)
- Limited by Pod's boto3 connection pool
- Risk of OOM for very large scans (10,000+ checks)

**Approach B:**
- Step Functions handles unlimited scale
- FastAPI triggers and exits immediately
- No in-memory state accumulation

- **Winner**: **Approach B** — better for large-scale scans

#### 9. **Development Experience**

| Aspect | Approach A | Approach B |
|--------|-----------|-----------|
| **Local Testing** | Easy (mock boto3) | Harder (need stepfunctions-local) |
| **Adding New Check** | Add to `REGISTERED_CHECKS` | Add to Choice state + Terraform |
| **Debugging** | Python debugger | Console + CloudWatch |
| **Unit Testing** | Standard pytest | Need moto + stepfunctions mocking |

- **Winner**: **Approach A** — simpler development workflow

#### 10. **Operational Considerations**

| Aspect | Approach A | Approach B |
|--------|-----------|-----------|
| **Pod Resource Needs** | Higher (holds state) | Lower (just triggers) |
| **Cold Start Impact** | Per-Lambda + per-invocation | Same Lambda impact |
| **Execution Timeout** | Pod timeout (300s default) | 5 min (Express) or 1 year (Standard) |
| **Stopping a Scan** | Kill background task (hard) | `sfn.stop_execution()` (easy) |
| **Audit Trail** | Build manually | Built into Step Functions |

- **Winner**: **Approach B** — better operational control

---

## Recommendation: When to Use Each

### Use **Approach A** (Direct Lambda) When:

1. **Cost is primary concern** — 10-15% cheaper per scan
2. **Simple orchestration needs** — No complex routing or conditionals
3. **Fast iteration** — Quick to add new checks without Terraform
4. **Small scale** — < 1,000 checks per scan
5. **Team familiarity** — Team knows Python better than Step Functions

### Use **Approach B** (Step Functions) When:

1. **Production reliability is critical** — Built-in retries, error isolation
2. **Large scale** — > 1,000 checks per scan regularly
3. **Need execution visibility** — Visual debugging, audit trail
4. **Complex orchestration** — Conditional checks, approval gates, human-in-loop
5. **Enterprise compliance** — Auditable execution history

---

## Migration Path: A → B

If starting with Approach A and need to migrate to B:

1. **Phase 1**: Deploy Step Functions alongside existing code
2. **Phase 2**: Feature flag to route 10% of scans to Step Functions
3. **Phase 3**: Monitor metrics, compare error rates
4. **Phase 4**: Gradually increase Step Functions traffic to 100%
5. **Phase 5**: Remove direct Lambda invocation code

```python
# Feature flag in scan router
if settings.USE_STEP_FUNCTIONS:
    await run_checks_via_stepfunctions(job_id, accounts, regions, checks)
else:
    background.add_task(_execute_scan, job_id, accounts, regions, checks)
```

---

## Final Verdict

| Criteria | Winner |
|----------|--------|
| **Reliability** | **Approach B** |
| **Scalability** | **Approach B** |
| **Observability** | **Approach B** |
| **Cost** | Approach A |
| **Development Speed** | Approach A |
| **Operational Control** | **Approach B** |
| **Overall for Production** | **Approach B** |

**For production workloads, Approach B (Step Functions) is recommended** because:

1. Built-in retry/backoff eliminates custom error-handling code
2. Hierarchical Map states provide better concurrency control
3. Visual execution history simplifies debugging
4. Native AWS integration for monitoring and alerting
5. Better fault isolation (one check failure doesn't affect others)

The ~10-15% cost increase is justified by:
- Reduced operational burden
- Faster incident resolution
- Built-in compliance audit trail
- Ability to handle 10x larger scans without refactoring

---

## Secure Networking Considerations & Implementation

This section covers the complete networking security architecture for the AWS Compliance Scanner.

### Network Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       VPC: compliance-scanner-vpc                                        │
│                                       CIDR: 10.0.0.0/16                                                  │
│                                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐│
│  │                                    PUBLIC SUBNETS (10.0.0.0/20)                                     ││
│  │                                                                                                      ││
│  │  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐                       ││
│  │  │  us-east-1a          │  │  us-east-1b          │  │  us-east-1c          │                       ││
│  │  │  10.0.0.0/24         │  │  10.0.1.0/24         │  │  10.0.2.0/24         │                       ││
│  │  │                      │  │                      │  │                      │                       ││
│  │  │  ├─ NAT Gateway      │  │  ├─ NAT Gateway      │  │  ├─ NAT Gateway      │                       ││
│  │  │  └─ ALB (public)     │  │  └─ ALB (public)     │  │  └─ ALB (public)     │                       ││
│  │  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘                       ││
│  │                                         │                                                            ││
│  │                                    Internet Gateway                                                  ││
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────┘│
│                                              │                                                           │
│                                              ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐│
│  │                                   PRIVATE SUBNETS (10.0.16.0/20)                                    ││
│  │                                                                                                      ││
│  │  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐                       ││
│  │  │  us-east-1a          │  │  us-east-1b          │  │  us-east-1c          │                       ││
│  │  │  10.0.16.0/24        │  │  10.0.17.0/24        │  │  10.0.18.0/24        │                       ││
│  │  │                      │  │                      │  │                      │                       ││
│  │  │  ├─ EKS Nodes        │  │  ├─ EKS Nodes        │  │  ├─ EKS Nodes        │                       ││
│  │  │  ├─ FastAPI Pods     │  │  ├─ FastAPI Pods     │  │  ├─ FastAPI Pods     │                       ││
│  │  │  └─ Istio Sidecar    │  │  └─ Istio Sidecar    │  │  └─ Istio Sidecar    │                       ││
│  │  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘                       ││
│  │                                                                                                      ││
│  │                               Route: 0.0.0.0/0 → NAT Gateway                                        ││
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────┘│
│                                              │                                                           │
│                                     VPC Endpoints                                                        │
│                                              │                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐│
│  │                              ISOLATED SUBNETS (10.0.32.0/20) — VPC Endpoints Only                   ││
│  │                                                                                                      ││
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐││
│  │  │  VPC Endpoints (PrivateLink)                                                                    │││
│  │  │                                                                                                  │││
│  │  │  ├─ com.amazonaws.us-east-1.states         (Step Functions)                                     │││
│  │  │  ├─ com.amazonaws.us-east-1.lambda         (Lambda)                                             │││
│  │  │  ├─ com.amazonaws.us-east-1.dynamodb       (DynamoDB - Gateway)                                 │││
│  │  │  ├─ com.amazonaws.us-east-1.sts            (STS)                                                │││
│  │  │  ├─ com.amazonaws.us-east-1.secretsmanager (Secrets Manager)                                    │││
│  │  │  ├─ com.amazonaws.us-east-1.logs           (CloudWatch Logs)                                    │││
│  │  │  ├─ com.amazonaws.us-east-1.ecr.api        (ECR API)                                            │││
│  │  │  ├─ com.amazonaws.us-east-1.ecr.dkr        (ECR Docker)                                         │││
│  │  │  └─ com.amazonaws.us-east-1.s3             (S3 - Gateway)                                       │││
│  │  └─────────────────────────────────────────────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────┘│
│                                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

### Module 1: VPC Configuration

```hcl
# terraform/network/vpc.tf

################################################################################
# VPC
################################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr  # 10.0.0.0/16
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

################################################################################
# VPC Flow Logs (Security Requirement)
################################################################################

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/${var.project_name}"
  retention_in_days = var.flow_log_retention_days  # 30

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "${var.project_name}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "${var.project_name}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}
```

---

### Module 2: Subnet Configuration

```hcl
# terraform/network/subnets.tf

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}

################################################################################
# Public Subnets (ALB, NAT Gateway)
################################################################################

resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)  # 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false  # Security: No auto-assign public IP

  tags = {
    Name                                        = "${var.project_name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "public"
  }
}

################################################################################
# Private Subnets (EKS Nodes, Application Pods)
################################################################################

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 16)  # 10.0.16.0/24, 10.0.17.0/24, 10.0.18.0/24
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.project_name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "private"
  }
}

################################################################################
# Isolated Subnets (VPC Endpoints Only - No Internet Access)
################################################################################

resource "aws_subnet" "isolated" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 32)  # 10.0.32.0/24, 10.0.33.0/24, 10.0.34.0/24
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-isolated-${local.azs[count.index]}"
    Tier = "isolated"
  }
}
```

---

### Module 3: NAT Gateway (High Availability)

```hcl
# terraform/network/nat_gateway.tf

################################################################################
# Elastic IPs for NAT Gateway (one per AZ for HA)
################################################################################

resource "aws_eip" "nat" {
  count  = var.enable_ha_nat ? length(local.azs) : 1
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

################################################################################
# NAT Gateways (Multi-AZ for High Availability)
################################################################################

resource "aws_nat_gateway" "main" {
  count         = var.enable_ha_nat ? length(local.azs) : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${local.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}
```

---

### Module 4: Route Tables

```hcl
# terraform/network/route_tables.tf

################################################################################
# Public Route Table
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Private Route Tables (one per AZ for HA NAT routing)
################################################################################

resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.enable_ha_nat ? aws_nat_gateway.main[count.index].id : aws_nat_gateway.main[0].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${local.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

################################################################################
# Isolated Route Table (No Internet Access)
################################################################################

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id

  # No routes to internet - only VPC endpoints

  tags = {
    Name = "${var.project_name}-isolated-rt"
  }
}

resource "aws_route_table_association" "isolated" {
  count          = length(aws_subnet.isolated)
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
```

---

### Module 5: VPC Endpoints (PrivateLink)

```hcl
# terraform/network/vpc_endpoints.tf

################################################################################
# Security Group for VPC Endpoints
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}

################################################################################
# Gateway Endpoints (S3, DynamoDB) - No Cost
################################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id]
  )

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id]
  )

  tags = {
    Name = "${var.project_name}-dynamodb-endpoint"
  }
}

################################################################################
# Interface Endpoints (PrivateLink)
################################################################################

locals {
  vpc_endpoints = {
    "states"         = "com.amazonaws.${var.aws_region}.states"          # Step Functions
    "lambda"         = "com.amazonaws.${var.aws_region}.lambda"          # Lambda
    "sts"            = "com.amazonaws.${var.aws_region}.sts"             # STS (for IRSA)
    "secretsmanager" = "com.amazonaws.${var.aws_region}.secretsmanager"  # Secrets
    "logs"           = "com.amazonaws.${var.aws_region}.logs"            # CloudWatch Logs
    "ecr-api"        = "com.amazonaws.${var.aws_region}.ecr.api"         # ECR API
    "ecr-dkr"        = "com.amazonaws.${var.aws_region}.ecr.dkr"         # ECR Docker
    "xray"           = "com.amazonaws.${var.aws_region}.xray"            # X-Ray
    "ssm"            = "com.amazonaws.${var.aws_region}.ssm"             # Systems Manager
    "kms"            = "com.amazonaws.${var.aws_region}.kms"             # KMS
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.vpc_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.isolated[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${each.key}-endpoint"
  }
}

################################################################################
# VPC Endpoint Policy for Step Functions (Restrict to our state machine)
################################################################################

resource "aws_vpc_endpoint_policy" "stepfunctions" {
  vpc_endpoint_id = aws_vpc_endpoint.interface["states"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOurStateMachine"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "states:StartExecution",
          "states:StartSyncExecution",
          "states:StopExecution",
          "states:DescribeExecution",
          "states:GetExecutionHistory"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
```

---

### Module 6: Security Groups

```hcl
# terraform/network/security_groups.tf

################################################################################
# ALB Security Group
################################################################################

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # HTTPS from Internet (or specific CIDRs for internal-only)
  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs  # ["0.0.0.0/0"] or specific ranges
  }

  # HTTP redirect only (optional)
  ingress {
    description = "HTTP for redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  # Outbound to EKS nodes only
  egress {
    description     = "To EKS nodes"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

################################################################################
# EKS Node Security Group
################################################################################

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # From ALB
  ingress {
    description     = "Application from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Istio Ingress Gateway
  ingress {
    description     = "Istio Ingress from ALB"
    from_port       = 15021
    to_port         = 15021
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Node-to-node communication
  ingress {
    description = "All traffic within nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # EKS Control Plane
  ingress {
    description     = "From EKS control plane"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    description     = "From EKS control plane (kubelet)"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # DNS (CoreDNS)
  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    self        = true
  }

  # Istio mTLS between sidecars
  ingress {
    description = "Istio mTLS"
    from_port   = 15012
    to_port     = 15012
    protocol    = "tcp"
    self        = true
  }

  # Envoy admin (health checks)
  ingress {
    description = "Envoy admin"
    from_port   = 15020
    to_port     = 15020
    protocol    = "tcp"
    self        = true
  }

  # All outbound (via NAT Gateway)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                        = "${var.project_name}-eks-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

################################################################################
# EKS Control Plane Security Group
################################################################################

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.main.id

  # From nodes
  ingress {
    description     = "From worker nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  # To nodes
  egress {
    description     = "To worker nodes (kubelet)"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description     = "To worker nodes (HTTPS)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

################################################################################
# Lambda Security Group (VPC-attached Lambdas)
################################################################################

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda functions in VPC"
  vpc_id      = aws_vpc.main.id

  # No inbound (Lambda is invoked, not called)

  # Outbound to VPC Endpoints
  egress {
    description     = "To VPC Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoints.id]
  }

  # Outbound to target accounts (via NAT for cross-region)
  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}
```

---

### Module 7: Network ACLs (Defense in Depth)

```hcl
# terraform/network/nacls.tf

################################################################################
# Public Subnet NACL
################################################################################

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Inbound HTTPS
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Inbound HTTP (for redirect)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Inbound ephemeral (return traffic)
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny SSH from Internet (explicit)
  ingress {
    protocol   = "tcp"
    rule_no    = 50
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # Deny RDP from Internet (explicit)
  ingress {
    protocol   = "tcp"
    rule_no    = 51
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 3389
    to_port    = 3389
  }

  # Outbound all
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-public-nacl"
  }
}

################################################################################
# Private Subnet NACL
################################################################################

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Inbound from VPC only
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Inbound ephemeral (return traffic from NAT)
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny SSH from public subnets (defense in depth)
  ingress {
    protocol   = "tcp"
    rule_no    = 50
    action     = "deny"
    cidr_block = cidrsubnet(var.vpc_cidr, 4, 0)  # 10.0.0.0/20 (public range)
    from_port  = 22
    to_port    = 22
  }

  # Outbound all
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-private-nacl"
  }
}

################################################################################
# Isolated Subnet NACL (VPC Endpoints Only)
################################################################################

resource "aws_network_acl" "isolated" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.isolated[*].id

  # Inbound HTTPS from VPC only (for VPC endpoints)
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  # Inbound ephemeral from VPC
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # DENY all from Internet (explicit)
  ingress {
    protocol   = "-1"
    rule_no    = 999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Outbound to VPC only
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-isolated-nacl"
  }
}
```

---

### Module 8: WAF (Web Application Firewall)

```hcl
# terraform/network/waf.tf

################################################################################
# WAF Web ACL
################################################################################

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "WAF for Compliance Scanner ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Exclude rules that may cause false positives
        rule_action_override {
          action_to_use {
            count {}
          }
          name = "SizeRestrictions_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - SQL Injection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000  # Requests per 5 minutes per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRuleMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Geo restriction (optional)
  rule {
    name     = "GeoBlockRule"
    priority = 5

    action {
      block {}
    }

    statement {
      geo_match_statement {
        country_codes = var.blocked_countries  # e.g., ["RU", "CN", "KP"]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlockRuleMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 6: IP Allowlist (if needed)
  rule {
    name     = "IPAllowlistRule"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.allowed_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPAllowlistRuleMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf-metric"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-waf"
  }
}

################################################################################
# IP Set for Allowlist
################################################################################

resource "aws_wafv2_ip_set" "allowed_ips" {
  name               = "${var.project_name}-allowed-ips"
  description        = "Allowed IP addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_addresses  # e.g., ["203.0.113.0/24"]

  tags = {
    Name = "${var.project_name}-allowed-ips"
  }
}

################################################################################
# Associate WAF with ALB
################################################################################

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

################################################################################
# WAF Logging
################################################################################

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  logging_filter {
    default_behavior = "KEEP"

    filter {
      behavior = "KEEP"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      requirement = "MEETS_ANY"
    }
  }
}

resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-waf-logs"
  }
}
```

---

### Module 9: Kubernetes Network Policies

```yaml
# kubernetes/network-policies/default-deny.yaml
# Default deny all ingress and egress in compliance namespace

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: compliance
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

```yaml
# kubernetes/network-policies/compliance-scanner-policy.yaml

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: compliance-scanner
  namespace: compliance
spec:
  podSelector:
    matchLabels:
      app: compliance-scanner
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # Allow from Istio Ingress Gateway only
    - from:
        - namespaceSelector:
            matchLabels:
              name: istio-system
          podSelector:
            matchLabels:
              istio: ingressgateway
      ports:
        - protocol: TCP
          port: 8080

    # Allow Prometheus scraping
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
          podSelector:
            matchLabels:
              app: prometheus
      ports:
        - protocol: TCP
          port: 9090

    # Allow from other compliance-scanner pods (Istio mTLS)
    - from:
        - podSelector:
            matchLabels:
              app: compliance-scanner
      ports:
        - protocol: TCP
          port: 15006  # Istio mTLS

  egress:
    # DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # AWS VPC Endpoints (private subnets)
    - to:
        - ipBlock:
            cidr: 10.0.32.0/20  # Isolated subnets with VPC endpoints
      ports:
        - protocol: TCP
          port: 443

    # External AWS APIs (via NAT Gateway for cross-region)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443

    # Istio control plane
    - to:
        - namespaceSelector:
            matchLabels:
              name: istio-system
      ports:
        - protocol: TCP
          port: 15012
        - protocol: TCP
          port: 15014
```

```yaml
# kubernetes/network-policies/istio-egress-policy.yaml

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio-egress
  namespace: compliance
spec:
  podSelector:
    matchLabels:
      app: compliance-scanner
  policyTypes:
    - Egress

  egress:
    # Istio sidecar to istiod
    - to:
        - namespaceSelector:
            matchLabels:
              name: istio-system
          podSelector:
            matchLabels:
              app: istiod
      ports:
        - protocol: TCP
          port: 15010
        - protocol: TCP
          port: 15012
        - protocol: TCP
          port: 15014
```

---

### Module 10: Istio Service Mesh Security

```yaml
# kubernetes/istio/peer-authentication.yaml
# Enforce mTLS for all pods in compliance namespace

apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: compliance
spec:
  mtls:
    mode: STRICT  # mTLS required for all pod-to-pod communication
```

```yaml
# kubernetes/istio/authorization-policy.yaml
# Restrict access to compliance-scanner

apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: compliance-scanner-authz
  namespace: compliance
spec:
  selector:
    matchLabels:
      app: compliance-scanner
  action: ALLOW
  rules:
    # Allow from Istio ingress gateway
    - from:
        - source:
            principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
      to:
        - operation:
            methods: ["GET", "POST", "PUT", "DELETE"]
            paths: ["/api/v1/*", "/healthz", "/readyz", "/metrics"]

    # Allow from Prometheus for metrics scraping
    - from:
        - source:
            namespaces: ["monitoring"]
            principals: ["cluster.local/ns/monitoring/sa/prometheus"]
      to:
        - operation:
            methods: ["GET"]
            paths: ["/metrics"]

    # Allow internal liveness/readiness probes (from kubelet)
    - from:
        - source:
            ipBlocks: ["10.0.0.0/8"]  # VPC CIDR
      to:
        - operation:
            methods: ["GET"]
            paths: ["/healthz", "/readyz"]
```

```yaml
# kubernetes/istio/destination-rule.yaml
# TLS settings and circuit breaker

apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: compliance-scanner
  namespace: compliance
spec:
  host: compliance-scanner
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL  # Use Istio's auto-generated certs
    
    connectionPool:
      tcp:
        maxConnections: 100
        connectTimeout: 10s
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        maxRequestsPerConnection: 10
        maxRetries: 3
    
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 30s
      baseEjectionTime: 60s
      maxEjectionPercent: 50
      minHealthPercent: 30
```

```yaml
# kubernetes/istio/request-authentication.yaml
# JWT validation (if using OIDC/OAuth)

apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: compliance-scanner-jwt
  namespace: compliance
spec:
  selector:
    matchLabels:
      app: compliance-scanner
  jwtRules:
    - issuer: "https://auth.company.com"
      jwksUri: "https://auth.company.com/.well-known/jwks.json"
      audiences:
        - "compliance-scanner-api"
      forwardOriginalToken: true
```

---

### Module 11: TLS/Certificate Management

```hcl
# terraform/network/acm.tf

################################################################################
# ACM Certificate for ALB
################################################################################

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name  # compliance-scanner.company.com
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

################################################################################
# ALB HTTPS Listener
################################################################################

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"  # TLS 1.3 + 1.2
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Redirect HTTP to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

---

### Module 12: Network Security Summary

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              NETWORK SECURITY CONTROLS SUMMARY                                           │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                          │
│  LAYER 1: EDGE SECURITY                                                                                  │
│  ━━━━━━━━━━━━━━━━━━━━━━━━                                                                               │
│  ✓ WAF with AWS Managed Rules (SQLi, XSS, common attacks)                                               │
│  ✓ Rate limiting (2000 req/5min per IP)                                                                 │
│  ✓ Geo-blocking (optional)                                                                              │
│  ✓ IP allowlist/blocklist                                                                               │
│  ✓ TLS 1.3/1.2 only (ELBSecurityPolicy-TLS13-1-2-2021-06)                                              │
│  ✓ ACM-managed certificates                                                                             │
│                                                                                                          │
│  LAYER 2: NETWORK SEGMENTATION                                                                           │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                          │
│  ✓ 3-tier subnet architecture (public, private, isolated)                                               │
│  ✓ Private subnets for EKS nodes (no direct internet access)                                            │
│  ✓ Isolated subnets for VPC endpoints only                                                              │
│  ✓ NAT Gateway (multi-AZ) for controlled outbound                                                       │
│  ✓ VPC Flow Logs to CloudWatch                                                                          │
│                                                                                                          │
│  LAYER 3: ACCESS CONTROL                                                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━                                                                              │
│  ✓ Security Groups (allow-list model)                                                                   │
│    - ALB SG: 443/80 from allowed CIDRs                                                                  │
│    - EKS Nodes SG: from ALB, k8s control plane only                                                     │
│    - VPC Endpoints SG: 443 from VPC only                                                                │
│  ✓ Network ACLs (defense in depth)                                                                      │
│    - Explicit SSH/RDP deny                                                                              │
│    - Isolated subnets: deny internet traffic                                                            │
│                                                                                                          │
│  LAYER 4: VPC ENDPOINTS (PRIVATELINK)                                                                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                   │
│  ✓ Step Functions endpoint (interface)                                                                  │
│  ✓ Lambda endpoint (interface)                                                                          │
│  ✓ DynamoDB endpoint (gateway)                                                                          │
│  ✓ S3 endpoint (gateway)                                                                                │
│  ✓ STS endpoint (interface) - for IRSA                                                                  │
│  ✓ Secrets Manager endpoint (interface)                                                                 │
│  ✓ CloudWatch Logs endpoint (interface)                                                                 │
│  ✓ ECR endpoints (interface) - for image pulls                                                          │
│  ✓ X-Ray endpoint (interface)                                                                           │
│  ✓ KMS endpoint (interface)                                                                             │
│                                                                                                          │
│  LAYER 5: KUBERNETES NETWORK POLICIES                                                                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                   │
│  ✓ Default deny all (zero trust)                                                                        │
│  ✓ Allow only from Istio ingress gateway                                                                │
│  ✓ Allow Prometheus scraping                                                                            │
│  ✓ Allow DNS (CoreDNS)                                                                                  │
│  ✓ Allow VPC endpoint CIDR for AWS API calls                                                            │
│                                                                                                          │
│  LAYER 6: SERVICE MESH (ISTIO)                                                                           │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                           │
│  ✓ mTLS STRICT mode (all pod-to-pod encrypted)                                                          │
│  ✓ AuthorizationPolicy (fine-grained access control)                                                    │
│  ✓ RequestAuthentication (JWT validation)                                                               │
│  ✓ Circuit breaker (outlier detection)                                                                  │
│  ✓ Automatic cert rotation (Citadel)                                                                    │
│                                                                                                          │
│  LAYER 7: APPLICATION SECURITY                                                                           │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                           │
│  ✓ API key authentication                                                                               │
│  ✓ Input validation (Pydantic schemas)                                                                  │
│  ✓ No secrets in environment variables (External Secrets Operator)                                      │
│  ✓ IRSA for AWS API authentication (no long-lived credentials)                                          │
│                                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

### Security Best Practices Checklist

| Category | Control | Status |
|----------|---------|--------|
| **Edge** | WAF enabled | ✅ |
| **Edge** | TLS 1.2+ only | ✅ |
| **Edge** | Rate limiting | ✅ |
| **Network** | Private subnets for workloads | ✅ |
| **Network** | VPC Flow Logs enabled | ✅ |
| **Network** | NAT Gateway (no direct IGW) | ✅ |
| **Network** | VPC Endpoints for AWS services | ✅ |
| **Access** | Security Groups (least privilege) | ✅ |
| **Access** | Network ACLs (defense in depth) | ✅ |
| **Access** | No SSH/RDP from internet | ✅ |
| **K8s** | Default deny NetworkPolicy | ✅ |
| **K8s** | Allow-list for pod communication | ✅ |
| **Mesh** | mTLS STRICT mode | ✅ |
| **Mesh** | AuthorizationPolicy | ✅ |
| **Mesh** | Circuit breaker | ✅ |
| **App** | No long-lived credentials | ✅ |
| **App** | Secrets from External Secrets | ✅ |
| **Audit** | CloudTrail enabled | ✅ |
| **Audit** | WAF logging | ✅ |
| **Audit** | VPC Flow Logs | ✅ |

---

### Variable Definitions

```hcl
# terraform/network/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "compliance-scanner"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "enable_ha_nat" {
  description = "Enable multi-AZ NAT Gateway for high availability"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period for VPC Flow Logs"
  type        = number
  default     = 30
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ip_addresses" {
  description = "IP addresses for WAF allowlist"
  type        = list(string)
  default     = []
}

variable "blocked_countries" {
  description = "Country codes to block via WAF geo-restriction"
  type        = list(string)
  default     = []
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}
```

---

### Outputs

```hcl
# terraform/network/outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EKS nodes)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB)"
  value       = aws_subnet.public[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs (for VPC endpoints)"
  value       = aws_subnet.isolated[*].id
}

output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "vpc_endpoints" {
  description = "VPC endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "nat_gateway_ips" {
  description = "NAT Gateway Elastic IPs"
  value       = aws_eip.nat[*].public_ip
}
```
