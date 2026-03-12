# AWS Compliance Scanner — Senior DevOps Engineer Interview Guide

> **Purpose**: Comprehensive scenario-based interview questions covering the complete lifecycle of the AWS Compliance Scanner application.
> 
> **Target Role**: Senior DevOps Engineer (L5/L6 equivalent)
> 
> **Topics Covered**: Monitoring, Incident Management, Availability, Scalability, Disaster Recovery, Reliability, Zero Downtime Deployment, Security, Architecture Improvements

---

## Table of Contents

1. [Architecture & Design Decisions](#1-architecture--design-decisions)
2. [Monitoring & Observability](#2-monitoring--observability)
3. [Alerting & Incident Management](#3-alerting--incident-management)
4. [Availability & Reliability](#4-availability--reliability)
5. [Scalability & Performance](#5-scalability--performance)
6. [Disaster Recovery](#6-disaster-recovery)
7. [Zero Downtime Deployment](#7-zero-downtime-deployment)
8. [Security](#8-security)
9. [Improvements from Approach A to B](#9-improvements-from-approach-a-to-b)
10. [Critical Issue Handling](#10-critical-issue-handling)
11. [Cost Optimization](#11-cost-optimization)
12. [Complete Application Deep Dive](#12-complete-application-deep-dive)

---

## 1. Architecture & Design Decisions

### Scenario 1.1: Why Step Functions over Direct Lambda?

**Q**: Walk me through the decision to migrate from direct Lambda invocation (Approach A) to Step Functions (Approach B). What problems did Approach A have?

**Expected Answer**:

**Approach A Problems:**
```
1. CONCURRENCY MANAGEMENT
   - Python Semaphore only limits per-pod concurrency
   - Multiple pods = uncontrolled Lambda invocation surge
   - Risk of hitting Lambda account limits (1000 concurrent)

2. ERROR HANDLING
   - asyncio.gather with return_exceptions=False: one failure breaks all
   - Manual retry logic = code complexity
   - No built-in exponential backoff

3. OBSERVABILITY GAP
   - Custom OTEL spans required for each step
   - No visual execution flow
   - Debugging requires grep through CloudWatch Logs

4. STATE MANAGEMENT
   - In-memory state during execution
   - Pod crash = lost execution state
   - No pause/resume capability

5. OPERATIONAL BURDEN
   - Stopping a scan = kill background task (hard)
   - No execution history
   - Limited audit trail
```

**Approach B Solutions:**
```
1. CONCURRENCY
   - Map state with MaxConcurrency per level
   - Account (10) × Region (5) × Check (15) = granular control
   - AWS manages Lambda throttling gracefully

2. ERROR HANDLING
   - Declarative Retry blocks with BackoffRate
   - Catch states for graceful degradation
   - Each check isolated — one failure doesn't cascade

3. OBSERVABILITY
   - Built-in execution graph in AWS Console
   - X-Ray integration native
   - Click-through debugging

4. STATE MANAGEMENT
   - AWS persists execution state
   - Durable across failures
   - Can stop/resume anytime

5. OPERATIONS
   - sfn.stop_execution() = instant stop
   - 90-day execution history
   - Full audit trail
```

---

### Scenario 1.2: Express vs Standard Workflow

**Q**: Why did you choose EXPRESS workflow type instead of STANDARD for the Step Functions state machine?

**Expected Answer**:

| Aspect | Express | Standard |
|--------|---------|----------|
| **Duration** | Max 5 minutes | Up to 1 year |
| **Execution Model** | Synchronous supported | Asynchronous only |
| **Cost** | Per state transition | Per state transition + duration |
| **Throughput** | 100,000/sec | 2,000/sec |
| **Execution History** | CloudWatch Logs only | Console + API (90 days) |

**Why Express:**
1. **Scan Duration**: Most scans complete in < 5 minutes
2. **Sync API Option**: `StartSyncExecution` allows blocking for small scans
3. **Cost**: Lower for high-frequency, short workloads
4. **Throughput**: Can handle burst of scan requests

**Trade-off Acknowledged:**
- Lose 90-day execution history in console (mitigated by CloudWatch Logs)
- Must handle large scans carefully (may exceed 5-minute limit)

---

## 2. Monitoring & Observability

### Scenario 2.1: What Metrics Do You Monitor?

**Q**: Describe the complete monitoring strategy for this application. What metrics do you track at each layer?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MONITORING STACK ARCHITECTURE                         │
│                                                                              │
│   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐             │
│   │   Prometheus   │◀──│  Application   │──▶│  CloudWatch    │             │
│   │   (EKS pods)   │   │   (FastAPI)    │   │  (AWS services)│             │
│   └───────┬────────┘   └────────────────┘   └───────┬────────┘             │
│           │                                          │                       │
│           ▼                                          ▼                       │
│   ┌────────────────┐                        ┌────────────────┐             │
│   │    Grafana     │                        │  CloudWatch    │             │
│   │   Dashboards   │                        │   Dashboards   │             │
│   └───────┬────────┘                        └───────┬────────┘             │
│           │                                          │                       │
│           └──────────────────┬───────────────────────┘                       │
│                              ▼                                               │
│                      ┌────────────────┐                                     │
│                      │  Alertmanager  │──▶ PagerDuty / Slack / OpsGenie    │
│                      └────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Layer 1: Infrastructure Metrics (Node/Cluster)**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `node_cpu_seconds_total` | node_exporter | > 80% for 5min |
| `node_memory_MemAvailable_bytes` | node_exporter | < 20% |
| `kubelet_running_pods` | kube-state-metrics | Near pod limit |
| `kube_node_status_condition` | kube-state-metrics | Not Ready |

**Layer 2: Application Metrics (FastAPI)**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `http_requests_total` | Prometheus FastAPI | - |
| `http_request_duration_seconds` | Prometheus FastAPI | p99 > 5s |
| `http_requests_total{status=~"5.."}` | Prometheus FastAPI | rate > 1% |
| `compliance_scan_jobs_running` | Custom gauge | > 50 for 10min |
| `compliance_scan_pass_rate` | Custom gauge | < 80% |
| `stepfunctions_executions_started` | Custom counter | - |

**Layer 3: Step Functions Metrics**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `ExecutionStarted` | CloudWatch | - |
| `ExecutionSucceeded` | CloudWatch | Success rate < 95% |
| `ExecutionFailed` | CloudWatch | > 0 in 5min |
| `ExecutionThrottled` | CloudWatch | > 0 |
| `ExecutionTime` | CloudWatch | p99 > 300s |

**Layer 4: Lambda Metrics (per function)**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `Invocations` | CloudWatch | - |
| `Duration` | CloudWatch | p99 > 250s |
| `Errors` | CloudWatch | rate > 5% |
| `Throttles` | CloudWatch | > 0 |
| `ConcurrentExecutions` | CloudWatch | > 80% of limit |
| `IteratorAge` (if SQS) | CloudWatch | > 60s |

**Layer 5: DynamoDB Metrics**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `ConsumedReadCapacityUnits` | CloudWatch | > 80% provisioned |
| `ConsumedWriteCapacityUnits` | CloudWatch | > 80% provisioned |
| `ThrottledRequests` | CloudWatch | > 0 |
| `SystemErrors` | CloudWatch | > 0 |
| `UserErrors` | CloudWatch | Spike detection |

**Layer 6: Istio Service Mesh**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `istio_requests_total` | Prometheus | - |
| `istio_request_duration_milliseconds` | Prometheus | p99 > 5000ms |
| `istio_tcp_connections_opened_total` | Prometheus | - |
| `envoy_cluster_circuit_breakers_default_cx_open` | Prometheus | > 0 |

---

### Scenario 2.2: Grafana Dashboard Design

**Q**: Design the main Grafana dashboard for this application. What panels would you include?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COMPLIANCE SCANNER - MAIN DASHBOARD                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │  SCANS TODAY    │  │   PASS RATE     │  │  ACTIVE SCANS   │              │
│  │     1,247       │  │     94.3%       │  │       12        │              │
│  │   ▲ 15% vs yday │  │   ▼ 2.1%       │  │                 │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  REQUEST RATE & ERROR RATE (last 6h)                                    ││
│  │                                                                          ││
│  │  100 ─┬────────────────────────────────────────────────────────         ││
│  │       │    Request Rate (rpm)                                           ││
│  │   50 ─┼──────────────────────────────────────────────────────           ││
│  │       │                              Error Rate (%)                     ││
│  │    0 ─┴────────────────────────────────────────────────────────         ││
│  │       00:00    02:00    04:00    06:00    08:00    10:00                ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌──────────────────────────────────┐  ┌───────────────────────────────────┐│
│  │  LATENCY HEATMAP (p50/p95/p99)   │  │  STEP FUNCTIONS EXECUTIONS       ││
│  │                                   │  │                                   ││
│  │  p99 ████████████░░░░░░ 4.2s     │  │  Started:    1,247                ││
│  │  p95 █████████░░░░░░░░░ 2.1s     │  │  Succeeded:  1,189  (95.3%)       ││
│  │  p50 ████░░░░░░░░░░░░░░ 0.8s     │  │  Failed:        42  (3.4%)        ││
│  │                                   │  │  Throttled:     16  (1.3%)        ││
│  └──────────────────────────────────┘  └───────────────────────────────────┘│
│                                                                              │
│  ┌──────────────────────────────────┐  ┌───────────────────────────────────┐│
│  │  COMPLIANCE BY CHECK TYPE        │  │  LAMBDA PERFORMANCE               ││
│  │                                   │  │                                   ││
│  │  cfn_drift        ███████░ 87%   │  │  Function         p99    Errors   ││
│  │  vpc_flow_logs    █████████ 96%  │  │  cfn-drift        4.2s   0.1%    ││
│  │  s3_encryption    ████████░ 91%  │  │  vpc-flow-logs    0.8s   0.0%    ││
│  │  iam_mfa          ██████░░░ 72%  │  │  s3-encryption    1.2s   0.2%    ││
│  │  sg_ssh           █████████ 98%  │  │  iam-mfa          2.1s   0.1%    ││
│  └──────────────────────────────────┘  └───────────────────────────────────┘│
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  BLUE/GREEN TRAFFIC DISTRIBUTION                                        ││
│  │                                                                          ││
│  │  BLUE  ████████████████████████████████████████████████████████ 100%    ││
│  │  GREEN ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0%    ││
│  │                                                                          ││
│  │  Last deployment: 2h 34m ago | Version: a1b2c3d                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌──────────────────────────────────┐  ┌───────────────────────────────────┐│
│  │  DYNAMODB PERFORMANCE            │  │  POD STATUS                       ││
│  │                                   │  │                                   ││
│  │  Read Capacity:   1,240 / 5,000  │  │  blue-7f8d9a-xxxxx    Running ✓   ││
│  │  Write Capacity:    890 / 2,500  │  │  blue-7f8d9a-yyyyy    Running ✓   ││
│  │  Throttles:              0       │  │  blue-7f8d9a-zzzzz    Running ✓   ││
│  │  Latency (p99):        12ms      │  │  green-8a9b0c-aaaaa   Running ✓   ││
│  └──────────────────────────────────┘  └───────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key PromQL Queries:**

```promql
# Request rate (RPM)
sum(rate(http_requests_total{app="compliance-scanner"}[1m])) * 60

# Error rate (%)
sum(rate(http_requests_total{app="compliance-scanner",status=~"5.."}[5m])) 
/ sum(rate(http_requests_total{app="compliance-scanner"}[5m])) * 100

# p99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{app="compliance-scanner"}[5m])) by (le))

# Blue/Green traffic split
sum(rate(istio_requests_total{destination_app="compliance-scanner",destination_version="blue"}[1m])) 
/ sum(rate(istio_requests_total{destination_app="compliance-scanner"}[1m])) * 100
```

---

### Scenario 2.3: End-to-End Tracing

**Q**: A scan takes 45 seconds. How do you identify which check is the bottleneck?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TRACE: scan-job-a1b2c3d4                              │
│                        Duration: 45.2s                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ├─ POST /api/v1/scan ─────────────────────────────────────── 45.2s        │
│  │   ├─ DynamoDB.PutItem (create job) ────────────────────── 12ms          │
│  │   ├─ StepFunctions.StartExecution ─────────────────────── 89ms          │
│  │   │   │                                                                  │
│  │   │   ├─ PrepareCheckTasks ────────────────────────────── 45ms          │
│  │   │   ├─ FanOutByAccount (Map) ────────────────────────── 44.8s ⚠️      │
│  │   │   │   │                                                              │
│  │   │   │   ├─ account:123456789012 ─────────────────────── 44.8s ⚠️      │
│  │   │   │   │   ├─ region:us-east-1 ─────────────────────── 44.2s ⚠️      │
│  │   │   │   │   │   ├─ cfn_drift ────────────────────────── 43.8s 🔴      │
│  │   │   │   │   │   │   └─ CFN.DetectStackDrift (50 stacks) ── 43.5s     │
│  │   │   │   │   │   ├─ vpc_flow_logs ────────────────────── 0.8s          │
│  │   │   │   │   │   ├─ s3_encryption ────────────────────── 1.2s          │
│  │   │   │   │   │   └─ ...                                                │
│  │   │   │   │   │                                                          │
│  │   │   │   │   └─ region:eu-west-1 ─────────────────────── 2.1s          │
│  │   │   │   │                                                              │
│  │   │   │   └─ account:987654321098 ─────────────────────── 3.2s          │
│  │   │   │                                                                  │
│  │   │   ├─ AggregateResults ─────────────────────────────── 156ms         │
│  │   │   └─ UpdateJobComplete ────────────────────────────── 23ms          │
│  │                                                                          │
│  └─ Response 202 ───────────────────────────────────────── 112ms           │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ BOTTLENECK: cfn_drift check for account 123456789012 / us-east-1           │
│ ROOT CAUSE: Account has 50 CloudFormation stacks; drift detection is slow  │
│ REMEDIATION: Parallelize drift detection within Lambda using ThreadPool    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**How to investigate:**

1. **Jaeger UI**: Filter by `job_id` tag, view waterfall
2. **Step Functions Console**: Click execution → View details → Click slow state
3. **CloudWatch Logs Insights**:
   ```sql
   fields @timestamp, @message
   | filter job_id = "a1b2c3d4"
   | filter @message like /duration/
   | sort @timestamp asc
   ```

4. **X-Ray Trace Map**: Visual representation of service dependencies

---

## 3. Alerting & Incident Management

### Scenario 3.1: Alert Design & Routing

**Q**: Design the alerting strategy. How do you avoid alert fatigue while ensuring critical issues are caught?

**Expected Answer**:

**Alert Severity Levels:**

| Severity | Response Time | Notification | Example |
|----------|--------------|--------------|---------|
| **P1 - Critical** | < 15 min | PagerDuty page + Slack | API completely down |
| **P2 - High** | < 1 hour | PagerDuty + Slack | Error rate > 5% |
| **P3 - Medium** | < 4 hours | Slack only | Error rate > 1% |
| **P4 - Low** | Next business day | Slack (digest) | Lambda p99 increased |

**AlertManager Configuration:**

```yaml
# alertmanager.yml
route:
  receiver: 'slack-default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  
  routes:
    # P1: Critical - Page immediately
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      group_wait: 0s
      repeat_interval: 5m
    
    # P2: High - Page during business hours, Slack after
    - match:
        severity: high
      receiver: 'pagerduty-high'
      group_wait: 30s
      repeat_interval: 30m
      routes:
        - match:
            time_of_day: outside_business_hours
          receiver: 'slack-urgent'
    
    # P3: Medium - Slack only
    - match:
        severity: medium
      receiver: 'slack-alerts'
      group_wait: 1m
      repeat_interval: 2h
    
    # P4: Low - Daily digest
    - match:
        severity: low
      receiver: 'slack-digest'
      group_wait: 30m
      repeat_interval: 24h

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: ${PAGERDUTY_CRITICAL_KEY}
        severity: critical
        
  - name: 'slack-alerts'
    slack_configs:
      - api_url: ${SLACK_WEBHOOK}
        channel: '#compliance-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

**Example Alerts:**

```yaml
# prometheus-rules.yml
groups:
  - name: compliance-scanner-critical
    rules:
      # P1: API down
      - alert: ComplianceScannerDown
        expr: up{job="compliance-scanner"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Compliance Scanner is DOWN"
          runbook_url: "https://wiki.company.com/runbooks/compliance-scanner-down"
      
      # P1: All Step Functions failing
      - alert: StepFunctionsAllFailing
        expr: |
          sum(rate(aws_states_executions_failed_total[5m])) 
          / sum(rate(aws_states_executions_started_total[5m])) > 0.5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Step Functions failure rate > 50%"

  - name: compliance-scanner-high
    rules:
      # P2: High error rate
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{app="compliance-scanner",status=~"5.."}[5m])) 
          / sum(rate(http_requests_total{app="compliance-scanner"}[5m])) > 0.05
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Error rate {{ $value | humanizePercentage }} exceeds 5%"
      
      # P2: Lambda throttling
      - alert: LambdaThrottling
        expr: sum(aws_lambda_throttles_total{function_name=~"compliance-.*"}) > 0
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Lambda functions are being throttled"

  - name: compliance-scanner-medium
    rules:
      # P3: Elevated latency
      - alert: ElevatedLatency
        expr: |
          histogram_quantile(0.99, 
            sum(rate(http_request_duration_seconds_bucket{app="compliance-scanner"}[5m])) by (le)
          ) > 5
        for: 10m
        labels:
          severity: medium
        annotations:
          summary: "p99 latency {{ $value }}s exceeds 5s threshold"
```

---

### Scenario 3.2: On-Call Runbook

**Q**: You're on-call and receive a P1 alert "Compliance Scanner Error Rate > 10%". Walk me through your incident response.

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    INCIDENT RESPONSE PLAYBOOK                                │
│                    Alert: High Error Rate (P1)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PHASE 1: ACKNOWLEDGE & ASSESS (0-5 min)                                    │
│  ────────────────────────────────────────────                               │
│                                                                              │
│  □ Acknowledge PagerDuty alert                                              │
│  □ Join incident Slack channel (#incident-YYYYMMDD-NNN)                     │
│  □ Check if recent deployment (GitLab → last pipeline)                      │
│    └─ If yes: Consider immediate rollback                                   │
│                                                                              │
│  Quick Assessment Commands:                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ # Check pod status                                                     │ │
│  │ kubectl get pods -n compliance -l app=compliance-scanner               │ │
│  │                                                                        │ │
│  │ # Check recent logs                                                    │ │
│  │ kubectl logs -n compliance -l app=compliance-scanner --tail=100        │ │
│  │                                                                        │ │
│  │ # Check error rate by endpoint                                         │ │
│  │ curl -s "$PROMETHEUS_URL/api/v1/query" \                               │ │
│  │   --data-urlencode 'query=sum by (endpoint) (                          │ │
│  │     rate(http_requests_total{status=~"5.."}[5m])                       │ │
│  │   )'                                                                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  PHASE 2: IDENTIFY BLAST RADIUS (5-10 min)                                  │
│  ─────────────────────────────────────────────                              │
│                                                                              │
│  □ Which endpoints are affected?                                            │
│    - /api/v1/scan (submit)                                                 │
│    - /api/v1/scan/{id} (get results)                                       │
│    - /healthz, /readyz                                                     │
│  □ Is it affecting Blue, Green, or both?                                   │
│  □ Is Step Functions healthy?                                               │
│  □ Are Lambda functions healthy?                                            │
│  □ Is DynamoDB healthy?                                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ # Check Step Functions recent executions                               │ │
│  │ aws stepfunctions list-executions \                                    │ │
│  │   --state-machine-arn $SFN_ARN \                                       │ │
│  │   --status-filter FAILED \                                             │ │
│  │   --max-results 5                                                      │ │
│  │                                                                        │ │
│  │ # Check Lambda errors                                                  │ │
│  │ aws logs filter-log-events \                                           │ │
│  │   --log-group-name /aws/lambda/compliance-check-cfn-drift \            │ │
│  │   --filter-pattern "ERROR" \                                           │ │
│  │   --start-time $(date -d '10 minutes ago' +%s000)                      │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  PHASE 3: MITIGATE (10-20 min)                                              │
│  ──────────────────────────────                                             │
│                                                                              │
│  Decision Tree:                                                              │
│                                                                              │
│  Is it a recent deployment? ──Yes─▶ ROLLBACK                                │
│          │                          kubectl patch vs compliance-scanner-vs  │
│          No                         --type=json -p='[{"op":"replace",...}]' │
│          │                                                                   │
│          ▼                                                                   │
│  Is it a specific Lambda? ──Yes──▶ DISABLE CHECK                            │
│          │                         Update Step Functions to skip check      │
│          No                                                                  │
│          │                                                                   │
│          ▼                                                                   │
│  Is DynamoDB throttling? ──Yes───▶ INCREASE CAPACITY                        │
│          │                         aws dynamodb update-table ...            │
│          No                                                                  │
│          │                                                                   │
│          ▼                                                                   │
│  Is it cross-account issue? ─Yes─▶ CHECK STS ASSUME ROLE                    │
│          │                         Verify target account role exists        │
│          No                                                                  │
│          │                                                                   │
│          ▼                                                                   │
│  ESCALATE to senior engineer                                                │
│                                                                              │
│  PHASE 4: RESOLVE & DOCUMENT (20+ min)                                      │
│  ──────────────────────────────────────                                     │
│                                                                              │
│  □ Implement fix (code change, config change, rollback)                    │
│  □ Verify error rate returning to normal                                   │
│  □ Close PagerDuty incident                                                │
│  □ Post to Slack: "Incident resolved. RCA to follow."                      │
│  □ Create JIRA ticket for RCA                                              │
│  □ Schedule blameless postmortem within 48h                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Availability & Reliability

### Scenario 4.1: How Do You Achieve 99.9% Availability?

**Q**: What architectural patterns ensure 99.9% availability for this application?

**Expected Answer**:

**SLA Breakdown:**
```
99.9% uptime = 8.76 hours downtime/year = 43.8 minutes/month
```

**Redundancy at Every Layer:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AVAILABILITY ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LAYER 1: DNS + LOAD BALANCING                                              │
│  ─────────────────────────────────                                          │
│  • Route 53 health checks (failover in 60s)                                 │
│  • Multi-AZ ALB (survives AZ failure)                                       │
│  • Connection draining (60s)                                                │
│                                                                              │
│  LAYER 2: KUBERNETES                                                         │
│  ────────────────────────                                                   │
│  • 3 replicas minimum (PodDisruptionBudget: minAvailable=2)                 │
│  • Anti-affinity (spread across AZs)                                        │
│  • Topology spread constraints                                              │
│  • Liveness/readiness probes                                                │
│  • PreStop hook (graceful shutdown)                                         │
│                                                                              │
│  LAYER 3: APPLICATION                                                        │
│  ─────────────────────                                                      │
│  • Stateless design (no in-memory state)                                    │
│  • Circuit breakers (Istio DestinationRule)                                 │
│  • Retry with exponential backoff                                           │
│  • Timeout configuration                                                    │
│  • Graceful degradation                                                     │
│                                                                              │
│  LAYER 4: STEP FUNCTIONS + LAMBDA                                           │
│  ───────────────────────────────────                                        │
│  • Step Functions: AWS managed (99.9% SLA)                                  │
│  • Lambda: Multi-AZ by default                                              │
│  • Reserved concurrency (prevents noisy neighbor)                           │
│  • Built-in retry (3 attempts, backoff)                                     │
│                                                                              │
│  LAYER 5: DATA                                                               │
│  ─────────────                                                              │
│  • DynamoDB: Multi-AZ, Global Tables for DR                                 │
│  • Point-in-time recovery enabled                                           │
│  • On-demand capacity (auto-scale)                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Kubernetes Configuration:**

```yaml
# deployment.yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: compliance-scanner
              topologyKey: topology.kubernetes.io/zone
      
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: compliance-scanner
      
      containers:
        - name: app
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 15"]
```

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: compliance-scanner-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: compliance-scanner
```

---

### Scenario 4.2: Circuit Breaker Implementation

**Q**: How do you prevent cascading failures when a Lambda function is unhealthy?

**Expected Answer**:

**Step Functions Retry + Circuit Breaker:**

```json
{
  "InvokeLambdaCheck": {
    "Type": "Task",
    "Resource": "arn:aws:states:::lambda:invoke",
    "Retry": [
      {
        "ErrorEquals": ["Lambda.TooManyRequestsException"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      },
      {
        "ErrorEquals": ["Lambda.ServiceException"],
        "IntervalSeconds": 1,
        "MaxAttempts": 2,
        "BackoffRate": 1.5
      }
    ],
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleCheckError"
      }
    ]
  }
}
```

**Istio Circuit Breaker:**

```yaml
# destinationrule.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: compliance-scanner-dr
spec:
  host: compliance-scanner
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
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

**Effect:**
- If a pod returns 3 consecutive 5xx errors → ejected for 60s
- Max 50% of pods can be ejected at once
- After 60s, pod is re-added to pool and monitored

---

## 5. Scalability & Performance

### Scenario 5.1: Handling a 10x Traffic Spike

**Q**: A major customer schedules scans of 500 accounts simultaneously. How does the system handle this?

**Expected Answer**:

**Current Capacity:**
- FastAPI: 3 pods × 4 workers = 12 concurrent requests
- Lambda per function: 50 reserved concurrency
- Step Functions Express: 100,000 executions/sec

**Scaling Mechanisms:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AUTO-SCALING ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LAYER 1: KUBERNETES HPA                                                     │
│  ────────────────────────────                                               │
│                                                                              │
│  apiVersion: autoscaling/v2                                                 │
│  kind: HorizontalPodAutoscaler                                              │
│  spec:                                                                       │
│    scaleTargetRef:                                                          │
│      apiVersion: apps/v1                                                    │
│      kind: Deployment                                                       │
│      name: compliance-scanner                                               │
│    minReplicas: 3                                                           │
│    maxReplicas: 20                                                          │
│    metrics:                                                                 │
│      - type: Resource                                                       │
│        resource:                                                            │
│          name: cpu                                                          │
│          target:                                                            │
│            type: Utilization                                                │
│            averageUtilization: 70                                           │
│      - type: Pods                                                           │
│        pods:                                                                │
│          metric:                                                            │
│            name: http_requests_per_second                                   │
│          target:                                                            │
│            type: AverageValue                                               │
│            averageValue: "100"                                              │
│                                                                              │
│  LAYER 2: STEP FUNCTIONS                                                     │
│  ────────────────────────────                                               │
│  • Express Workflow: No execution limit                                     │
│  • Map state MaxConcurrency limits Lambda burst                             │
│  • Account=10 × Region=5 × Check=15 = 750 concurrent per scan              │
│                                                                              │
│  LAYER 3: LAMBDA                                                             │
│  ──────────────────                                                         │
│  • Reserved concurrency: 50 per function                                    │
│  • Provisioned concurrency for critical checks: 10                          │
│  • Account limit: 1000 concurrent (can request increase)                    │
│                                                                              │
│  LAYER 4: DYNAMODB                                                           │
│  ─────────────────────                                                      │
│  • On-demand capacity: Auto-scales to millions of requests                  │
│  • No capacity planning required                                            │
│  • Partition key design avoids hot partitions                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Calculation for 500 Accounts:**
```
500 accounts × 5 regions × 15 checks = 37,500 Lambda invocations

Step Functions Map MaxConcurrency:
- Account level: 10 concurrent
- Region level: 5 concurrent per account = 50 max
- Check level: 15 concurrent per region = 750 max

With 50 reserved concurrency per Lambda:
- 15 functions × 50 = 750 total Lambda concurrency
- Matches Step Functions concurrency → no throttling

Estimated time:
- 37,500 invocations / 750 concurrent = 50 batches
- If each batch takes 30s average → ~25 minutes total
```

---

### Scenario 5.2: Lambda Cold Start Optimization

**Q**: How do you minimize Lambda cold start impact on scan latency?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    LAMBDA COLD START OPTIMIZATION                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  STRATEGY 1: PROVISIONED CONCURRENCY (for critical checks)                  │
│  ────────────────────────────────────────────────────────────                │
│                                                                              │
│  resource "aws_lambda_provisioned_concurrency_config" "cfn_drift" {         │
│    function_name                     = aws_lambda_function.cfn_drift.name   │
│    qualifier                         = aws_lambda_alias.cfn_drift_live.name │
│    provisioned_concurrent_executions = 10                                   │
│  }                                                                           │
│                                                                              │
│  Cost: ~$15/month per 10 provisioned (always warm)                          │
│  Benefit: 0ms cold start for first 10 concurrent invocations                │
│                                                                              │
│  STRATEGY 2: OPTIMIZED PACKAGE SIZE                                          │
│  ────────────────────────────────────                                       │
│                                                                              │
│  Before: 50MB (boto3 + dependencies bundled)                                │
│  After:  5MB  (use Lambda layer for boto3)                                  │
│                                                                              │
│  resource "aws_lambda_layer_version" "boto3" {                              │
│    layer_name = "boto3-latest"                                              │
│    compatible_runtimes = ["python3.12"]                                     │
│    s3_bucket  = aws_s3_bucket.lambda_layers.id                              │
│    s3_key     = "layers/boto3.zip"                                          │
│  }                                                                           │
│                                                                              │
│  Cold start: 50MB → 800ms, 5MB → 200ms                                      │
│                                                                              │
│  STRATEGY 3: MINIMIZE IMPORTS                                                │
│  ─────────────────────────────                                              │
│                                                                              │
│  # Bad: Imports entire boto3                                                │
│  import boto3                                                               │
│  client = boto3.client('cloudformation')                                    │
│                                                                              │
│  # Good: Lazy import inside handler                                         │
│  def handler(event, context):                                               │
│      import boto3                                                           │
│      client = boto3.client('cloudformation')                                │
│                                                                              │
│  STRATEGY 4: KEEP-WARM PATTERN (for low-traffic periods)                    │
│  ─────────────────────────────────────────────────────────                  │
│                                                                              │
│  # EventBridge rule: ping every 5 minutes                                   │
│  resource "aws_cloudwatch_event_rule" "keep_warm" {                         │
│    name                = "lambda-keep-warm"                                 │
│    schedule_expression = "rate(5 minutes)"                                  │
│  }                                                                           │
│                                                                              │
│  # Lambda handler checks for warm-up event                                  │
│  def handler(event, context):                                               │
│      if event.get("source") == "aws.events":                                │
│          return {"statusCode": 200, "body": "warm"}                         │
│      # ... actual logic                                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Disaster Recovery

### Scenario 6.1: Multi-Region DR Strategy

**Q**: The primary region (us-east-1) experiences a complete outage. How quickly can you recover?

**Expected Answer**:

**DR Tier: Warm Standby**

| Component | RTO | RPO | Strategy |
|-----------|-----|-----|----------|
| DynamoDB | 0 | 0 | Global Tables (active-active) |
| EKS Cluster | 15 min | 0 | Pre-provisioned, 0 replicas |
| Lambda | 0 | 0 | Deployed in both regions |
| Step Functions | 0 | 0 | Deployed in both regions |
| ECR | 0 | 0 | Cross-region replication |
| Route 53 | 60s | 0 | Health check failover |

**Failover Procedure:**

```bash
#!/bin/bash
# dr-failover.sh — Execute in us-west-2

echo "🚨 Initiating DR failover to us-west-2..."

# 1. Scale up EKS pods in DR region
kubectl scale deployment compliance-scanner-blue -n compliance \
  --replicas=3 --context=eks-us-west-2

# 2. Verify DynamoDB Global Table is active
aws dynamodb describe-table --table-name compliance-scan-jobs \
  --region us-west-2 --query 'Table.TableStatus'

# 3. Update Route 53 to force traffic to DR (if health check hasn't already)
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "compliance-scanner.company.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "alb-us-west-2.company.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# 4. Verify Step Functions state machine exists
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:us-west-2:$ACCOUNT_ID:stateMachine:compliance-scanner-orchestrator"

# 5. Smoke test
curl -sf https://compliance-scanner.company.com/healthz

echo "✅ Failover complete. Traffic now routing to us-west-2"
```

---

### Scenario 6.2: Data Recovery

**Q**: Someone accidentally deleted all scan results from the last 24 hours. How do you recover?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DATA RECOVERY OPTIONS                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  OPTION 1: POINT-IN-TIME RECOVERY (PITR)                                    │
│  ──────────────────────────────────────────                                 │
│                                                                              │
│  # DynamoDB PITR is enabled, retains 35 days                                │
│                                                                              │
│  aws dynamodb restore-table-to-point-in-time \                              │
│    --source-table-name compliance-scan-results \                            │
│    --target-table-name compliance-scan-results-restored \                   │
│    --restore-date-time "2024-03-08T12:00:00Z"                               │
│                                                                              │
│  # After restore, merge data back                                           │
│  python scripts/merge_dynamodb_tables.py \                                  │
│    --source compliance-scan-results-restored \                              │
│    --target compliance-scan-results \                                       │
│    --filter "timestamp >= 2024-03-08"                                       │
│                                                                              │
│  RTO: ~30 minutes for 1GB of data                                           │
│  RPO: 0 (any point in last 35 days)                                         │
│                                                                              │
│  OPTION 2: RE-RUN SCANS (if PITR not fast enough)                           │
│  ─────────────────────────────────────────────────                          │
│                                                                              │
│  # Get list of jobs from last 24h                                           │
│  aws dynamodb query \                                                       │
│    --table-name compliance-scan-jobs \                                      │
│    --index-name created-at-index \                                          │
│    --key-condition-expression "created_at > :yesterday" \                   │
│    --expression-attribute-values '{":yesterday":{"S":"2024-03-08"}}'        │
│                                                                              │
│  # Re-submit each job                                                       │
│  for job_id in $JOB_IDS; do                                                 │
│    curl -X POST /api/v1/scan/$job_id/rescan -H "X-API-Key: $KEY"           │
│  done                                                                       │
│                                                                              │
│  RTO: Depends on scan volume                                                │
│  RPO: 0 (re-scans current state)                                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Zero Downtime Deployment

### Scenario 7.1: Blue/Green Deployment Deep Dive

**Q**: Walk me through exactly what happens during a deployment. How do you guarantee zero dropped requests?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ZERO DOWNTIME DEPLOYMENT TIMELINE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  T+0:00 — PIPELINE TRIGGERED                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████████ 100%               │
│            GREEN                                           0%               │
│                                                                              │
│  • New commit merged to main                                                │
│  • Build stage: Kaniko builds new image (3 min)                             │
│  • Security scan: Trivy + Bandit (2 min)                                    │
│                                                                              │
│  T+5:00 — GREEN DEPLOYMENT STARTS                                           │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                             │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████████ 100%               │
│            GREEN                                           0%               │
│                                                                              │
│  • ArgoCD syncs green overlay                                               │
│  • Kubernetes creates new green pod                                         │
│  • Pod starts, initializes                                                  │
│                                                                              │
│  T+6:00 — GREEN POD READY                                                   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━                                                 │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████████ 100%               │
│            GREEN                                           0%               │
│                                                                              │
│  • Readiness probe passes (/readyz returns 200)                             │
│  • Pod added to green Service endpoints                                     │
│  • Still receiving 0% traffic                                               │
│                                                                              │
│  T+7:00 — CANARY STARTS (10% traffic to green)                              │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                 │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████░░░░ 90%                │
│            GREEN ████                                     10%               │
│                                                                              │
│  kubectl patch virtualservice compliance-scanner-vs \                       │
│    --type=json -p='[                                                        │
│      {"op":"replace","path":"/spec/http/1/route/0/weight","value":90},     │
│      {"op":"replace","path":"/spec/http/1/route/1/weight","value":10}      │
│    ]'                                                                       │
│                                                                              │
│  • Istio Envoy receives config update (~1 second)                           │
│  • In-flight requests to blue complete normally                             │
│  • New requests distributed 90/10                                           │
│                                                                              │
│  T+7:00 → T+12:00 — CANARY BAKE (5 minutes)                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                 │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████░░░░ 90%                │
│            GREEN ████                                     10%               │
│                                                                              │
│  Monitoring:                                                                │
│  • Error rate: < 1% ✓                                                       │
│  • Latency p99: < 5s ✓                                                      │
│  • Step Functions success rate: > 95% ✓                                     │
│  • /healthz returns 200 ✓                                                   │
│                                                                              │
│  T+12:00 — PROMOTE: 100% to GREEN                                           │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                          │
│                                                                              │
│  Traffic:  BLUE                                            0%               │
│            GREEN ████████████████████████████████████████ 100%              │
│                                                                              │
│  kubectl patch virtualservice compliance-scanner-vs \                       │
│    --type=json -p='[                                                        │
│      {"op":"replace","path":"/spec/http/1/route/0/weight","value":0},      │
│      {"op":"replace","path":"/spec/http/1/route/1/weight","value":100}     │
│    ]'                                                                       │
│                                                                              │
│  T+12:30 — UPDATE BLUE TO MATCH GREEN                                       │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                       │
│                                                                              │
│  • ArgoCD syncs blue overlay with new image                                 │
│  • Blue pods rolling update (maxUnavailable: 0)                             │
│                                                                              │
│  T+14:00 — ROUTE BACK TO BLUE                                               │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                              │
│                                                                              │
│  Traffic:  BLUE ████████████████████████████████████████ 100%               │
│            GREEN                                           0%               │
│                                                                              │
│  • Both blue and green now run new version                                  │
│  • Blue is primary (3 replicas)                                             │
│  • Green is standby (1 replica)                                             │
│                                                                              │
│  ZERO DROPPED REQUESTS BECAUSE:                                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                             │
│                                                                              │
│  1. New pods must pass readiness before traffic                             │
│  2. Istio updates are atomic (no partial config)                            │
│  3. In-flight requests complete before pod termination                      │
│  4. PreStop hook delays pod termination 15s                                 │
│  5. Connection draining at ALB level                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Scenario 7.2: Rollback Scenario

**Q**: The canary shows 5% error rate after 2 minutes. What happens?

**Expected Answer**:

```
T+9:00 — VERIFY STAGE DETECTS ISSUE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Error rate: 5.2% (threshold: 1%)

GitLab CI verify:canary job fails → exit code 1

T+9:01 — AUTOMATIC ROLLBACK TRIGGERED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"when: on_failure" triggers rollback:green job

Traffic:  BLUE ████████████████████████████████████████ 100%  (immediate)
          GREEN                                           0%

kubectl patch virtualservice compliance-scanner-vs \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":100},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":0}
  ]'

Time to rollback: < 5 seconds (Istio config push)

T+9:02 — ALERTS SENT
━━━━━━━━━━━━━━━━━━━━━

• PagerDuty incident created
• Slack notification: "🚨 Deployment rollback..."
• GitLab pipeline marked failed
• Green pods continue running (for debugging)

CUSTOMER IMPACT:
━━━━━━━━━━━━━━━━━

• Duration: ~2 minutes at 10% traffic
• Affected requests: ~12 out of 120 during window
• Error rate seen by customers: ~1% (10% × 10%)
```

---

## 8. Security

### Scenario 8.1: Cross-Account Access Security

**Q**: How do you securely scan 100 different AWS accounts without storing long-lived credentials?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CROSS-ACCOUNT ACCESS ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SCANNER ACCOUNT (111111111111)                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                       │   │
│  │  EKS Pod                                                              │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │  Service Account: compliance-scanner-sa                         │ │   │
│  │  │  ↓                                                              │ │   │
│  │  │  IRSA (IAM Role for Service Accounts)                           │ │   │
│  │  │  Role: compliance-scanner-eks-role                              │ │   │
│  │  │  ↓                                                              │ │   │
│  │  │  Permissions: sts:AssumeRole on target accounts                 │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                       │   │
│  │  Lambda: compliance-check-*                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │  Execution Role: compliance-scanner-lambda-role                 │ │   │
│  │  │  ↓                                                              │ │   │
│  │  │  Permissions: sts:AssumeRole on target accounts                 │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│                              ║                                               │
│                              ║  STS AssumeRole                               │
│                              ║  (with ExternalId)                            │
│                              ▼                                               │
│                                                                              │
│  TARGET ACCOUNT (222222222222)                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                       │   │
│  │  IAM Role: ComplianceScannerRole                                     │   │
│  │                                                                       │   │
│  │  Trust Policy:                                                        │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │  {                                                              │ │   │
│  │  │    "Version": "2012-10-17",                                     │ │   │
│  │  │    "Statement": [{                                              │ │   │
│  │  │      "Effect": "Allow",                                         │ │   │
│  │  │      "Principal": {                                             │ │   │
│  │  │        "AWS": "arn:aws:iam::111111111111:role/compliance-*"    │ │   │
│  │  │      },                                                         │ │   │
│  │  │      "Action": "sts:AssumeRole",                                │ │   │
│  │  │      "Condition": {                                             │ │   │
│  │  │        "StringEquals": {                                        │ │   │
│  │  │          "sts:ExternalId": "compliance-scanner-v1-RANDOM"       │ │   │ ← Prevents confused deputy
│  │  │        }                                                        │ │   │
│  │  │      }                                                          │ │   │
│  │  │    }]                                                           │ │   │
│  │  │  }                                                              │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                       │   │
│  │  Attached Policies:                                                   │   │
│  │  • arn:aws:iam::aws:policy/SecurityAudit (read-only security)        │   │
│  │  • arn:aws:iam::aws:policy/ReadOnlyAccess (limited resources)        │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

SECURITY CONTROLS:
━━━━━━━━━━━━━━━━━━

1. NO LONG-LIVED CREDENTIALS
   - IRSA injects temporary STS tokens (1h expiry)
   - Lambda execution role has STS permissions only
   - Credentials never stored, always on-demand

2. EXTERNAL ID (Confused Deputy Prevention)
   - Unique external ID per customer
   - Stored in AWS Secrets Manager
   - Prevents malicious service from assuming role

3. PRINCIPLE OF LEAST PRIVILEGE
   - SecurityAudit policy: read-only on security-related APIs
   - No write permissions in target accounts
   - Explicit deny on sensitive operations

4. AUDIT TRAIL
   - CloudTrail logs all AssumeRole calls
   - Lambda execution logged with account_id context
   - Correlation via job_id across all systems
```

---

### Scenario 8.2: Secret Management

**Q**: How are API keys and sensitive configuration managed?

**Expected Answer**:

```yaml
# External Secrets Operator — syncs AWS Secrets Manager to k8s Secrets

apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: compliance-scanner-secrets
  namespace: compliance
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: compliance-scanner-secrets
    creationPolicy: Owner
  data:
    - secretKey: API_KEYS
      remoteRef:
        key: compliance-scanner/api-keys
        property: keys
    - secretKey: PAGERDUTY_KEY
      remoteRef:
        key: compliance-scanner/pagerduty
        property: routing_key
    - secretKey: CROSS_ACCOUNT_EXTERNAL_IDS
      remoteRef:
        key: compliance-scanner/external-ids
        property: ids
```

```yaml
# Deployment references secret
containers:
  - name: app
    env:
      - name: API_KEYS
        valueFrom:
          secretKeyRef:
            name: compliance-scanner-secrets
            key: API_KEYS
```

---

## 9. Improvements from Approach A to B

### Scenario 9.1: What Did You Improve?

**Q**: What specific problems did Approach A have that Approach B solves?

**Expected Answer**:

| Problem (Approach A) | Impact | Solution (Approach B) |
|---------------------|--------|----------------------|
| **Semaphore-based concurrency** | Hard to tune; doesn't scale across pods | Step Functions Map MaxConcurrency |
| **Manual retry logic** | Code complexity; inconsistent backoff | Declarative Retry blocks |
| **In-memory execution state** | Pod crash = lost state | AWS-managed execution history |
| **asyncio.gather failures** | One check failure affects all | Isolated Map iterations |
| **No execution visibility** | grep through logs to debug | Step Functions Console |
| **Stopping a scan** | Kill background task (data loss) | `stop_execution()` API |
| **No built-in audit trail** | Manual logging required | 90-day execution history |
| **ThreadPoolExecutor overhead** | Thread creation per invocation | AWS manages concurrency |

**Quantified Improvements:**

```
RELIABILITY:
• Error isolation: 0% → 100% (each check independent)
• Retry success rate: ~60% → ~95% (built-in backoff)

OBSERVABILITY:
• Mean time to identify bottleneck: 30min → 5min
• Trace correlation: Manual OTEL → Automatic X-Ray

OPERATIONS:
• Deployment rollback time: 30s → 5s (no background tasks)
• On-call debugging: grep logs → click Step Functions Console

SCALABILITY:
• Max concurrent checks: 20 (semaphore) → 750 (nested Maps)
• Max scan size: ~500 checks → ~10,000 checks

COST:
• Slight increase (~10-15%) justified by above improvements
```

---

## 10. Critical Issue Handling

### Scenario 10.1: Production Database Corruption

**Q**: You discover that a bug in the result-aggregator Lambda caused incorrect data to be written to DynamoDB for the last 4 hours. How do you handle this?

**Expected Answer**:

```
PHASE 1: IMMEDIATE RESPONSE (0-15 min)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ACKNOWLEDGE & ASSESS
   • Identify affected time range: 08:00 - 12:00 UTC
   • Estimate affected jobs: ~1,200 scan jobs
   • Determine corruption type: incorrect status values

2. STOP THE BLEEDING
   • Deploy hotfix or rollback result-aggregator Lambda
   • Option A: aws lambda update-alias --routing-config {} (100% to previous version)
   • Option B: Deploy fixed code via GitLab CI

3. COMMUNICATE
   • Post to #incident channel
   • Draft customer communication (if external impact)

PHASE 2: DATA RECOVERY (15-60 min)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Option A: PITR Restore
┌────────────────────────────────────────────────────────────────────────────┐
│ aws dynamodb restore-table-to-point-in-time \                              │
│   --source-table-name compliance-scan-results \                            │
│   --target-table-name compliance-scan-results-07-59 \                      │
│   --restore-date-time "2024-03-09T07:59:00Z"                               │
│                                                                            │
│ # Compare and merge                                                        │
│ python scripts/compare_tables.py \                                         │
│   --corrupted compliance-scan-results \                                    │
│   --clean compliance-scan-results-07-59 \                                  │
│   --time-range "08:00-12:00"                                               │
└────────────────────────────────────────────────────────────────────────────┘

Option B: Re-run affected scans
┌────────────────────────────────────────────────────────────────────────────┐
│ # Get affected job IDs                                                     │
│ aws dynamodb query \                                                       │
│   --table-name compliance-scan-jobs \                                      │
│   --index-name created-at-index \                                          │
│   --key-condition-expression "created_at BETWEEN :start AND :end"          │
│                                                                            │
│ # Delete corrupted results                                                 │
│ for job_id in $AFFECTED_JOBS; do                                           │
│   aws dynamodb delete-item --table-name compliance-scan-results \          │
│     --key '{"pk": "'$job_id'"}'                                            │
│ done                                                                       │
│                                                                            │
│ # Re-trigger scans                                                         │
│ for job_id in $AFFECTED_JOBS; do                                           │
│   curl -X POST /api/v1/scan/$job_id/rescan                                 │
│ done                                                                       │
└────────────────────────────────────────────────────────────────────────────┘

PHASE 3: ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. What was the bug?
   • Example: JSON parsing error when Lambda returned null resource_id
   
2. Why wasn't it caught?
   • Unit tests didn't cover null case
   • Integration tests used mocked responses
   
3. Prevention measures:
   • Add test case for null resource_id
   • Implement schema validation in result-aggregator
   • Add data quality check in post-deploy smoke test

PHASE 4: POST-INCIDENT
━━━━━━━━━━━━━━━━━━━━━━

• Blameless postmortem document
• Action items with owners and due dates
• Share learnings in team meeting
```

---

## 11. Cost Optimization

### Scenario 11.1: Cost Breakdown

**Q**: What are the main cost drivers for this application and how would you optimize them?

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MONTHLY COST BREAKDOWN (ESTIMATE)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  COMPUTE (EKS)                                        $450/month            │
│  ━━━━━━━━━━━━━                                                              │
│  • 3 × m5.large nodes ($0.096/hr × 24 × 30)        = $207                  │
│  • EKS control plane                                = $72                   │
│  • Load Balancer                                    = $18                   │
│  • NAT Gateway                                      = $45                   │
│  • Data transfer                                    = $108                  │
│                                                                              │
│  LAMBDA                                               $120/month            │
│  ━━━━━━━                                                                    │
│  • 100,000 invocations × 15 functions              = 1.5M invocations       │
│  • Average duration: 2s @ 256MB                    = ~$100                  │
│  • Provisioned concurrency (cfn-drift)             = ~$20                   │
│                                                                              │
│  STEP FUNCTIONS                                       $30/month             │
│  ━━━━━━━━━━━━━━                                                             │
│  • 100,000 scans × ~100 state transitions          = 10M transitions        │
│  • Express Workflow: $0.000001/transition          = ~$10                   │
│  • CloudWatch Logs                                 = ~$20                   │
│                                                                              │
│  DYNAMODB                                             $50/month             │
│  ━━━━━━━━                                                                   │
│  • On-demand: ~5M WCU, ~10M RCU                    = ~$30                   │
│  • Storage: ~10GB                                  = ~$3                    │
│  • Global Tables replication                       = ~$17                   │
│                                                                              │
│  OBSERVABILITY                                        $100/month            │
│  ━━━━━━━━━━━━━                                                              │
│  • CloudWatch Logs (retention 30 days)             = ~$40                   │
│  • CloudWatch Metrics                              = ~$20                   │
│  • X-Ray traces                                    = ~$20                   │
│  • Prometheus (self-hosted, storage)               = ~$20                   │
│                                                                              │
│  ECR                                                  $10/month             │
│  ━━━                                                                        │
│  • Image storage (~5GB)                            = ~$5                    │
│  • Cross-region replication                        = ~$5                    │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│  TOTAL ESTIMATED                                      ~$760/month           │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  OPTIMIZATION OPPORTUNITIES:                                                 │
│                                                                              │
│  1. SPOT INSTANCES FOR EKS WORKERS                   -30% on compute        │
│     • Use mixed instance policy (70% Spot, 30% On-Demand)                   │
│     • Implement node termination handler                                    │
│     • Savings: ~$60/month                                                   │
│                                                                              │
│  2. GRAVITON (ARM) INSTANCES                         -20% on compute        │
│     • m6g.large instead of m5.large                                         │
│     • Requires ARM container images                                         │
│     • Savings: ~$40/month                                                   │
│                                                                              │
│  3. LAMBDA ARM                                       -20% on Lambda         │
│     • arm64 architecture = 20% cheaper                                      │
│     • Same or better performance                                            │
│     • Savings: ~$24/month                                                   │
│                                                                              │
│  4. LOG RETENTION                                    -50% on logs           │
│     • Reduce from 30 days to 7 days                                         │
│     • Archive to S3 Glacier for compliance                                  │
│     • Savings: ~$20/month                                                   │
│                                                                              │
│  5. RESERVED CAPACITY                                                       │
│     • 1-year reserved: ~30% savings on steady-state                         │
│     • Savings: ~$100/month (if committed)                                   │
│                                                                              │
│  POTENTIAL OPTIMIZED TOTAL                            ~$500/month           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 12. Complete Application Deep Dive

### Scenario 12.1: Walk Me Through the Entire System

**Q**: Explain the complete request lifecycle from a user clicking "Scan" to seeing results.

**Expected Answer**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            COMPLETE REQUEST LIFECYCLE: POST /api/v1/scan                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. CLIENT REQUEST                                                           │
│  ━━━━━━━━━━━━━━━━━                                                          │
│                                                                              │
│  POST https://compliance-scanner.company.com/api/v1/scan                    │
│  Headers:                                                                   │
│    X-API-Key: sk-xxxx-yyyy-zzzz                                             │
│    Content-Type: application/json                                           │
│    traceparent: 00-abc123-def456-01                                         │
│  Body:                                                                      │
│    {                                                                        │
│      "account_ids": ["123456789012"],                                       │
│      "regions": ["us-east-1"],                                              │
│      "checks": ["vpc_flow_logs", "s3_encryption"]                           │
│    }                                                                        │
│                                                                              │
│  2. DNS RESOLUTION                                                           │
│  ━━━━━━━━━━━━━━━━                                                           │
│                                                                              │
│  Route 53 → ALB (us-east-1) → Target Group                                  │
│  Health check: /healthz returns 200                                         │
│                                                                              │
│  3. LOAD BALANCER                                                            │
│  ━━━━━━━━━━━━━━━                                                            │
│                                                                              │
│  ALB terminates TLS (ACM certificate)                                       │
│  X-Forwarded-* headers added                                                │
│  Routes to EKS NodePort / Istio Ingress Gateway                             │
│                                                                              │
│  4. ISTIO INGRESS GATEWAY                                                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━                                                   │
│                                                                              │
│  Gateway resource: HTTPS on port 443                                        │
│  VirtualService matches: /api/v1/*                                          │
│  Weighted routing: blue=100%, green=0%                                      │
│  mTLS: STRICT mode                                                          │
│                                                                              │
│  5. ISTIO ENVOY SIDECAR                                                      │
│  ━━━━━━━━━━━━━━━━━━━━━━                                                     │
│                                                                              │
│  Injects tracing headers (x-b3-traceid, x-b3-spanid)                        │
│  Applies circuit breaker rules                                              │
│  Routes to compliance-scanner pod                                           │
│                                                                              │
│  6. FASTAPI APPLICATION                                                      │
│  ━━━━━━━━━━━━━━━━━━━━━━                                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  @router.post("")                                                       │ │
│  │  async def submit_scan(request: ScanRequest):                           │ │
│  │      # 6a. Validate API key                                             │ │
│  │      api_key = verify_api_key(request.headers["X-API-Key"])             │ │
│  │                                                                         │ │
│  │      # 6b. Generate job_id                                              │ │
│  │      job_id = str(uuid.uuid4())  # "a1b2c3d4-..."                       │ │
│  │                                                                         │ │
│  │      # 6c. Create job in DynamoDB (status=PENDING)                      │ │
│  │      repo.create_job({                                                  │ │
│  │          "job_id": job_id,                                              │ │
│  │          "status": "PENDING",                                           │ │
│  │          "account_ids": ["123456789012"],                               │ │
│  │          ...                                                            │ │
│  │      })                                                                 │ │
│  │                                                                         │ │
│  │      # 6d. Start Step Functions execution                               │ │
│  │      sfn_client.start_execution(                                        │ │
│  │          stateMachineArn="arn:aws:states:...:compliance-scanner-...",   │ │
│  │          name=f"scan-{job_id}",                                         │ │
│  │          input=json.dumps({                                             │ │
│  │              "job_id": job_id,                                          │ │
│  │              "account_ids": ["123456789012"],                           │ │
│  │              "regions": ["us-east-1"],                                  │ │
│  │              "checks": ["vpc_flow_logs", "s3_encryption"],              │ │
│  │              "trace_context": {"traceparent": "..."}                    │ │
│  │          })                                                             │ │
│  │      )                                                                  │ │
│  │                                                                         │ │
│  │      # 6e. Return 202 Accepted                                          │ │
│  │      return {"job_id": job_id, "status": "PENDING"}                     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  CLIENT RECEIVES: 202 Accepted + job_id                                     │
│  LATENCY: ~200ms                                                            │
│                                                                              │
│  7. STEP FUNCTIONS EXECUTION (async, background)                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                            │
│                                                                              │
│  State 1: PrepareCheckTasks                                                 │
│    • DynamoDB UpdateItem: status = "RUNNING"                                │
│                                                                              │
│  State 2: FanOutByAccount (Map, MaxConcurrency=10)                          │
│    • Input: ["123456789012"]                                                │
│    • Iterates each account                                                  │
│                                                                              │
│  State 3: FanOutByRegion (nested Map, MaxConcurrency=5)                     │
│    • Input: ["us-east-1"]                                                   │
│    • Iterates each region                                                   │
│                                                                              │
│  State 4: FanOutByCheck (nested Map, MaxConcurrency=15)                     │
│    • Input: ["vpc_flow_logs", "s3_encryption"]                              │
│    • Iterates each check                                                    │
│                                                                              │
│  State 5: RouteToCheck (Choice)                                             │
│    • $.check_id == "vpc_flow_logs" → InvokeVpcFlowLogsCheck                │
│    • $.check_id == "s3_encryption" → InvokeS3EncryptionCheck               │
│                                                                              │
│  State 6: InvokeVpcFlowLogsCheck (Task - Lambda)                            │
│    ┌──────────────────────────────────────────────────────────────────────┐│
│    │  Lambda: compliance-check-vpc-flow-logs:live                         ││
│    │                                                                       ││
│    │  def handler(event, context):                                         ││
│    │      account_id = event["account_id"]  # "123456789012"              ││
│    │      region = event["region"]          # "us-east-1"                 ││
│    │                                                                       ││
│    │      # Assume cross-account role                                      ││
│    │      sts = boto3.client("sts")                                        ││
│    │      creds = sts.assume_role(                                         ││
│    │          RoleArn=f"arn:aws:iam::{account_id}:role/ComplianceScanner",││
│    │          ExternalId="compliance-scanner-v1"                           ││
│    │      )["Credentials"]                                                 ││
│    │                                                                       ││
│    │      # Use temporary credentials                                      ││
│    │      ec2 = boto3.client("ec2",                                        ││
│    │          region_name=region,                                          ││
│    │          aws_access_key_id=creds["AccessKeyId"],                      ││
│    │          ...                                                          ││
│    │      )                                                                ││
│    │                                                                       ││
│    │      # Check VPC flow logs                                            ││
│    │      vpcs = ec2.describe_vpcs()["Vpcs"]                               ││
│    │      flow_logs = ec2.describe_flow_logs()["FlowLogs"]                 ││
│    │                                                                       ││
│    │      vpcs_with_logs = {fl["ResourceId"] for fl in flow_logs}          ││
│    │      vpcs_without = [v for v in vpcs if v["VpcId"] not in vpcs_with_logs]││
│    │                                                                       ││
│    │      if vpcs_without:                                                 ││
│    │          return {                                                     ││
│    │              "check_id": "vpc_flow_logs",                             ││
│    │              "status": "FAILED",                                      ││
│    │              "message": f"VPCs missing flow logs: {vpcs_without}",    ││
│    │              "remediation": "Enable VPC Flow Logs for all VPCs"       ││
│    │          }                                                            ││
│    │      return {"check_id": "vpc_flow_logs", "status": "PASSED", ...}    ││
│    └──────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  State 7: AggregateResults (Lambda)                                         │
│    • Flattens nested Map results                                            │
│    • Batch writes to DynamoDB scan-results table                            │
│    • Returns: {total: 2, passed: 1, failed: 1, errors: 0}                   │
│                                                                              │
│  State 8: UpdateJobComplete (DynamoDB UpdateItem)                           │
│    • status = "COMPLETED"                                                   │
│    • passed = 1, failed = 1, errors = 0                                     │
│    • completed_at = timestamp                                               │
│                                                                              │
│  TOTAL EXECUTION TIME: ~5 seconds (for 2 checks × 1 account × 1 region)    │
│                                                                              │
│  8. CLIENT POLLS FOR RESULTS                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                │
│                                                                              │
│  GET /api/v1/scan/a1b2c3d4-...                                              │
│                                                                              │
│  Response:                                                                  │
│  {                                                                          │
│    "job_id": "a1b2c3d4-...",                                                │
│    "status": "COMPLETED",                                                   │
│    "total_checks": 2,                                                       │
│    "passed": 1,                                                             │
│    "failed": 1,                                                             │
│    "results": [                                                             │
│      {                                                                      │
│        "check_id": "vpc_flow_logs",                                         │
│        "status": "FAILED",                                                  │
│        "message": "VPCs missing flow logs: [vpc-12345]",                    │
│        "remediation": "Enable VPC Flow Logs for all VPCs"                   │
│      },                                                                     │
│      {                                                                      │
│        "check_id": "s3_encryption",                                         │
│        "status": "PASSED",                                                  │
│        "message": "All S3 buckets have default encryption enabled"          │
│      }                                                                      │
│    ]                                                                        │
│  }                                                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary: Key Points for Interview

1. **Always explain the WHY** — Don't just describe; explain why you made each decision
2. **Quantify impact** — "Improved from X to Y" is stronger than "made it better"
3. **Acknowledge trade-offs** — Nothing is perfect; show you understand costs
4. **Show operational mindset** — Monitoring, alerting, runbooks, on-call
5. **Security first** — IRSA, least privilege, no long-lived credentials
6. **Be specific** — Use actual metrics, commands, configurations
7. **Connect to business outcomes** — Reliability = customer trust = revenue

---

*Document Version: 2.0*  
*Last Updated: March 2026*  
*Application: AWS Compliance Scanner B (Step Functions)*
