# AWS Compliance Scanner — Production Application

> **What it does**: Scans AWS resources across multiple accounts and regions for security and operational best-practice compliance, exposing results via a RESTful FastAPI deployed on EKS with Istio, GitOps via ArgoCD, Blue/Green deployments, and full observability.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [End-to-End Request Flow](#end-to-end-request-flow)
3. [Project Structure](#project-structure)
4. [Compliance Checks Implemented](#compliance-checks-implemented)
5. [Blue/Green Deployment Strategy](#bluegreen-deployment-strategy)
6. [E2E Tracing (OpenTelemetry → Jaeger / X-Ray)](#e2e-tracing)
7. [Monitoring & Alerting](#monitoring--alerting)
8. [Disaster Recovery](#disaster-recovery)
9. [Security Architecture](#security-architecture)
10. [Key Parameters & Configuration](#key-parameters--configuration)
11. [Local Development](#local-development)
12. [Deployment Runbook](#deployment-runbook)
13. [Scenario-Based Interview Questions](#scenario-based-interview-questions)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                        AWS COMPLIANCE SCANNER — PRODUCTION                           │
│                                                                                      │
│   CLIENT                                                                             │
│     │                                                                                │
│     ▼                                                                                │
│  ┌──────────────────────────────────────────────────────────┐                       │
│  │              AWS EKS CLUSTER (us-east-1)                  │                       │
│  │                                                           │                       │
│  │  ┌─────────────────┐                                     │                       │
│  │  │  Istio Ingress  │◀── HTTPS (ACM TLS)                  │                       │
│  │  │    Gateway       │                                     │                       │
│  │  └────────┬────────┘                                     │                       │
│  │           │  VirtualService — weighted routing            │                       │
│  │     ┌─────┴──────────────────────────┐                   │                       │
│  │     │                                │                   │                       │
│  │  ┌──▼──────────────┐   ┌─────────────▼──────────────┐   │                       │
│  │  │  BLUE Deployment │   │   GREEN Deployment          │   │                       │
│  │  │  (100% stable)   │   │   (0→10%→100% canary)       │   │                       │
│  │  │                  │   │                             │   │                       │
│  │  │  FastAPI App     │   │  FastAPI App (new version)  │   │                       │
│  │  │  3 replicas      │   │  1 replica                  │   │                       │
│  │  │  IRSA → DynamoDB │   │  IRSA → DynamoDB            │   │                       │
│  │  │  IRSA → Lambda   │   │  IRSA → Lambda              │   │                       │
│  │  └──────────────────┘   └─────────────────────────────┘   │                       │
│  │                                                           │                       │
│  └──────────────────────────────────────────────────────────┘                       │
│                │                                                                      │
│                │  AWS SDK (async Lambda.Invoke × 15 checks × N accounts × M regions) │
│                ▼                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                    AWS LAMBDA (compliance-check-*)                               │ │
│  │                                                                                  │ │
│  │  cfn-drift  │  vpc-flow-logs  │  audit-manager  │  s3-encryption │  iam-mfa     │ │
│  │  cloudtrail │  sg-ssh         │  guardduty      │  rds-encryption│  ebs-encrypt │ │
│  │  config-rec │  secrets-rot    │  ecr-scanning   │  eks-logging   │  ...         │ │
│  │                                                                                  │ │
│  │  Each Lambda assumes cross-account role:  ComplianceScannerRole                  │ │
│  │  Returns: { status: PASSED|FAILED|ERROR, message, remediation }                  │ │
│  └──────────────────────────────────────────────────────────────────────────────────┘ │
│                │                                                                      │
│                │  Store results                                                       │
│                ▼                                                                      │
│  ┌────────────────────────────────┐   ┌────────────────────────────────────────────┐ │
│  │  DynamoDB — compliance-scan-   │   │  DynamoDB Global Tables                    │ │
│  │  jobs  (job state + summary)   │◀─▶│  (replicated to us-west-2 for DR)          │ │
│  │  results (per-check results)   │   └────────────────────────────────────────────┘ │
│  └────────────────────────────────┘                                                  │
│                                                                                      │
│  OBSERVABILITY STACK (monitoring namespace)                                          │
│  ┌──────────────┐ ┌───────────────┐ ┌─────────────────┐ ┌────────────────────────┐ │
│  │  Prometheus  │ │ Grafana       │ │  Jaeger (OTEL)  │ │  CloudWatch Insights   │ │
│  │  + Alertmanager│ Dashboards   │ │  Trace viewer   │ │  Lambda + EKS logs     │ │
│  └──────────────┘ └───────────────┘ └─────────────────┘ └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## End-to-End Request Flow

```
POST /api/v1/scan
{
  "account_ids": ["123456789012", "987654321098"],
  "regions": ["us-east-1", "eu-west-1"],
  "checks": ["cfn_drift", "vpc_flow_logs"]
}
```

**Step-by-step:**

```
1. Client ──HTTPS──▶ Route 53 ──▶ ALB ──▶ Istio Ingress Gateway
         TLS termination at ALB (ACM cert) or Gateway (credentialName)

2. Istio VirtualService matches /api/v1 → routes to BLUE (100%) or BLUE/GREEN weighted

3. FastAPI (scan router):
   a. Validates API key from X-API-Key header
   b. Creates a Job record in DynamoDB (status=PENDING)
   c. Returns 202 Accepted with job_id immediately
   d. Kicks off background task (asyncio)

4. Background task (lambda_invoker.py):
   a. Builds list of (check, account_id, region) tuples
      = 2 checks × 2 accounts × 2 regions = 8 Lambda invocations
   b. Acquires asyncio Semaphore (MAX_CONCURRENT=20)
   c. ThreadPoolExecutor.run_in_executor → boto3 Lambda.invoke (sync)
   d. Each Lambda call:
      i.  boto3 STS.assume_role → cross-account credentials
      ii. Lambda.invoke("compliance-check-cfn-drift", payload={job_id, account, region})
      iii. Lambda runs CFN drift detection → returns {status, message, remediation}
   e. All results collected via asyncio.gather

5. FastAPI: stores each result in DynamoDB scan-results table
   Updates job record: status=COMPLETED, passed=X, failed=Y

6. Client polls:
   GET /api/v1/scan/{job_id}
   → Returns full job with all check results

7. Observability at every step:
   - OTEL span created per request and per Lambda call
   - Trace-context propagated into Lambda payload (W3C TraceContext headers)
   - Lambda SDK reads trace context → child spans in same trace
   - Spans exported to OTEL Collector → Jaeger / AWS X-Ray
   - Metrics exposed at /metrics → Prometheus scrapes → Grafana dashboards
```

---

## Project Structure

```
aws-compliance-scanner/
├── .gitlab-ci.yml                        # Full CI/CD pipeline (lint→test→build→deploy→promote)
│
├── fastapi-app/                          # Application source code
│   ├── Dockerfile                        # Multi-stage, non-root, read-only FS
│   ├── requirements.txt
│   └── app/
│       ├── main.py                       # FastAPI app, middleware, OTEL, Prometheus
│       ├── config.py                     # Pydantic Settings from env vars
│       ├── database.py                   # DynamoDB / RDS abstraction (Repository pattern)
│       ├── schemas.py                    # Request/Response Pydantic models
│       ├── routers/
│       │   ├── scan.py                   # POST /scan, GET /scan, GET /scan/{id}, POST /rescan
│       │   └── health.py                 # GET /healthz, /readyz, /metrics/summary
│       └── services/
│           ├── lambda_invoker.py         # Async fan-out, semaphore, cross-account IRSA
│           └── tracer.py                 # OTEL TracerProvider setup
│
├── lambda-functions/                     # One directory per compliance check
│   ├── cfn-drift-check/handler.py
│   ├── vpc-flow-logs-check/handler.py
│   ├── audit-manager-check/handler.py
│   ├── s3-encryption-check/handler.py
│   ├── iam-mfa-check/handler.py
│   ├── cloudtrail-check/handler.py
│   └── sg-unrestricted-ssh-check/handler.py
│
├── k8s/
│   ├── base/                             # Kustomize base (shared across slots)
│   │   ├── namespace.yaml               # compliance ns,  istio-injection: enabled
│   │   ├── serviceaccount.yaml          # IRSA annotation
│   │   ├── configmap.yaml               # App configuration
│   │   ├── deployment.yaml              # 3 replicas, anti-affinity, topology spread
│   │   ├── service.yaml                 # ClusterIP
│   │   ├── hpa.yaml                     # CPU + memory + custom metric
│   │   ├── pdb.yaml                     # minAvailable: 2
│   │   └── kustomization.yaml
│   │
│   ├── overlays/
│   │   ├── blue/                        # Production (stable) slot
│   │   │   ├── deployment-patch.yaml    # slot=blue label, SLOT=blue env
│   │   │   ├── service-patch.yaml       # Selector: slot=blue
│   │   │   └── kustomization.yaml
│   │   └── green/                       # Canary (new version) slot
│   │       ├── deployment-patch.yaml    # slot=green label, 1 replica
│   │       ├── service-patch.yaml       # Selector: slot=green
│   │       └── kustomization.yaml
│   │
│   └── istio/
│       ├── gateway.yaml                 # HTTPS + HTTP→HTTPS redirect
│       ├── virtualservice.yaml          # Weighted routing (blue:green)
│       ├── destinationrule.yaml         # mTLS, circuit breaker, load balancing
│       └── peerauthentication.yaml      # STRICT mTLS + AuthorizationPolicy
│
├── argocd/
│   ├── argocd-project.yaml              # AppProject with RBAC + sync windows
│   ├── application-blue.yaml            # ArgoCD App for blue slot
│   ├── application-green.yaml           # ArgoCD App for green slot
│   └── app-of-apps.yaml                 # Root App-of-Apps
│
└── terraform/
    ├── main.tf                           # Providers, S3 backend
    ├── variables.tf
    ├── outputs.tf
    ├── eks.tf                            # EKS, VPC, Istio + ArgoCD Helm, node groups
    ├── iam.tf                            # Lambda role, IRSA role, cross-account template
    ├── lambda.tf                         # Lambda functions, aliases, ECR repo
    └── dynamodb.tf                       # scan-jobs + scan-results tables, KMS, Global Tables
```

---

## Compliance Checks Implemented

| Check ID | Check Name | Severity | API Used |
|----------|-----------|----------|---------|
| `cfn_drift` | CloudFormation Stack Drift | HIGH | cfn.detect_stack_drift |
| `vpc_flow_logs` | VPC Flow Logs Enabled | HIGH | ec2.describe_flow_logs |
| `audit_manager_enabled` | AWS Audit Manager Active | MEDIUM | auditmanager.get_settings |
| `s3_encryption` | S3 Default Encryption | HIGH | s3.get_bucket_encryption |
| `iam_mfa_root` | Root Account MFA | CRITICAL | iam.get_account_summary |
| `iam_mfa_users` | IAM Users MFA | HIGH | iam.list_mfa_devices |
| `cloudtrail_enabled` | CloudTrail Multi-Region | HIGH | cloudtrail.describe_trails |
| `sg_unrestricted_ssh` | No Open SSH 0.0.0.0/0 | CRITICAL | ec2.describe_security_groups |
| `rds_encryption` | RDS Encryption at Rest | HIGH | rds.describe_db_instances |
| `ebs_encryption` | EBS Volume Encryption | MEDIUM | ec2.describe_volumes |
| `guardduty_enabled` | GuardDuty Enabled | HIGH | guardduty.list_detectors |
| `config_recorder` | AWS Config Recorder | MEDIUM | config.describe_configuration_recorders |
| `secrets_manager_rotation` | Secrets Auto-Rotation | MEDIUM | secretsmanager.list_secrets |
| `ecr_image_scanning` | ECR Scan on Push | MEDIUM | ecr.describe_repositories |
| `eks_cluster_logging` | EKS Control Plane Logs | MEDIUM | eks.describe_cluster |

---

## Blue/Green Deployment Strategy

### Overview

```
                           ISTIO VIRTUALSERVICE WEIGHTS
                           ─────────────────────────────
  Day 0 (normal):          BLUE=100%, GREEN=0%
  After green deploy:      BLUE=90%,  GREEN=10%   ← canary
  After bake period:       BLUE=0%,   GREEN=100%  ← full green
  After blue update:       BLUE=100%, GREEN=0%    ← complete swap
  On rollback:             BLUE=100%, GREEN=0%    ← instant revert
```

### Blue/Green Flow (CI-Driven)

```
GitLab CI Pipeline (on merge to main)
│
├── 1. lint / test / security-scan
│
├── 2. build:fastapi-image (Kaniko → ECR)
│   └── Tags: ${COMMIT_SHA}, latest
│
├── 3. build:lambda-packages (zip each check)
│
├── 4. deploy:green
│   ├── Patch k8s/overlays/green/kustomization.yaml with new image tag
│   ├── git commit + push (GitOps) → ArgoCD auto-syncs green deployment
│   ├── argocd app sync compliance-scanner-green + wait for health
│   └── kubectl patch VirtualService → GREEN weight = 10%
│
├── 5. verify:canary (sleep 5min, check CloudWatch error rate + /healthz)
│   ├── PASS → promote stage
│   └── FAIL → rollback stage (automatic)
│
├── 6a. promote:blue-green-swap (on verify success)
│   ├── Shift VirtualService → GREEN=100%
│   ├── Wait 30s
│   ├── Patch k8s/overlays/blue/ to green's image tag
│   ├── ArgoCD sync blue (blue now has new code)
│   ├── Shift VirtualService back → BLUE=100%, GREEN=0%
│   └── Tag ECR image as :stable
│
└── 6b. rollback:green (on verify failure — automatic)
    ├── kubectl patch VirtualService → BLUE=100%, GREEN=0%
    └── Slack alert
```

### Lambda Blue/Green

Lambda uses **versioned aliases** (:live) with CodeDeploy-style weight shifting:

```
Lambda: compliance-check-cfn-drift
  Version $1 (old):  :live  → 100% (before deploy)
  Version $2 (new):  :live  → 10% weight for 5 minutes, then → 100%
```

The GitLab pipeline uses `update-alias` with `AdditionalVersionWeights` during the canary phase, then removes the split after promotion.

---

## E2E Tracing

### Architecture

```
Client Request
     │
     │  HTTP headers: traceparent, tracestate (W3C TraceContext)
     ▼
Istio Envoy Proxy
     │  Injects x-b3-traceid, x-b3-spanid into headers
     ▼
FastAPI (OTEL FastAPI Instrumentor — auto-creates root span)
     │  TraceID: abc123...
     │
     ├── Span: POST /api/v1/scan  [FastAPI root]
     │
     ├── Span: run_checks_async   [lambda_invoker.py]
     │    ├── Propagates W3C TraceContext into Lambda payload
     │    │
     │    ├── Span: compliance-check-cfn-drift/account=123/region=us-east-1
     │    │    └── Lambda reads traceparent from event, creates child span via OTEL
     │    │
     │    ├── Span: compliance-check-vpc-flow-logs/account=123/region=us-east-1
     │    │
     │    └── ... (15 checks × N accounts × M regions)
     │
     └── Span: DynamoDB.PutItem  [auto-instrumented via OTEL boto3 plugin]

All spans exported to OTEL Collector → Jaeger / AWS X-Ray
TraceID is consistent across FastAPI + all Lambdas
```

### OTEL Configuration

- **Exporter**: `OTLPSpanExporter` → OpenTelemetry Collector (in-cluster, sidecar or DaemonSet)
- **Collector destinations**: Jaeger (for UI), AWS X-Ray (for production audit)
- **Sampling**: 100% for errors, 10% for success traces (head-based sampling at collector)
- **Trace context propagated into Lambda**: `$.trace_context.traceparent`

### Lambda OTEL (optional, add to each handler)

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.propagators.b3 import B3MultiFormat
from opentelemetry.propagate import extract

def handler(event, context):
    # Extract trace context from Step Functions / FastAPI payload
    carrier  = event.get("trace_context", {})
    ctx      = extract(carrier)
    tracer   = trace.get_tracer("compliance-check")
    with tracer.start_as_current_span("cfn-drift-check", context=ctx) as span:
        span.set_attribute("account_id", event["account_id"])
        # ... check logic
```

---

## Monitoring & Alerting

### Metrics (Prometheus / Grafana)

| Metric | Source | Alert Condition |
|--------|--------|----------------|
| `http_request_duration_seconds` | Prometheus FastAPI Instrumentator | p99 > 5s |
| `http_requests_total{status="5xx"}` | Prometheus | rate > 1% for 5min |
| `compliance_scan_jobs_running` | Custom `/metrics` endpoint | > 50 for 10min |
| `compliance_scan_pass_rate` | Custom gauge | < 80% |
| `lambda_duration_ms` | CloudWatch | p99 > 250s |
| `lambda_errors` | CloudWatch | rate > 5% |
| `istio_requests_total` | Istio telemetry | error rate by version |
| `kube_deployment_status_replicas_available` | kube-state-metrics | < minAvailable |
| `node_cpu_seconds_total` | node_exporter | > 80% for 5min |

### Grafana Dashboards

1. **Compliance Overview**: Pass rate by account, check type, severity heat map
2. **API Performance**: Latency P50/P95/P99, throughput, error rate
3. **Blue/Green Status**: Traffic weights, error rates per slot, deployment timeline
4. **Lambda Performance**: Duration, concurrent executions, error rate per check
5. **EKS Cluster**: Node CPU/memory, pod scheduling, HPA activity
6. **Istio Service Mesh**: mTLS status, circuit breaker trips, retries

### CloudWatch Alarms

```
compliance-scanner-high-error-rate   → SNS → PagerDuty
compliance-lambda-timeout             → SNS → Slack
compliance-eks-pod-crash-looping      → SNS → Slack
compliance-dynamodb-throttled         → SNS → Slack
```

---

## Disaster Recovery

### Strategy: Active-Active Primary / Warm Standby Secondary

| Component | Primary (us-east-1) | Secondary (us-west-2) | RTO | RPO |
|-----------|--------------------|-----------------------|-----|-----|
| EKS Cluster | Active | Warm (pre-provisioned, 0 replicas) | 15 min | 0 |
| DynamoDB | Active | Global Tables replica (automatic) | 0 | 0 |
| Lambda | Deployed | Deployed (same code) | 0 | 0 |
| ECR | Active | Replication rule → us-west-2 | 0 | 0 |
| Route 53 | Primary routing | Health-check failover | 60s | 0 |
| ArgoCD | Active | Backup config in Git | 30 min | 0 |

### Failover Steps

```bash
# 1. Trigger Route 53 health check failover (automated)
#    Primary ALB health check fails → DNS shifts to secondary ALB

# 2. Scale up secondary EKS cluster
kubectl scale deployment compliance-scanner-blue -n compliance \
  --replicas=3 --context=eks-us-west-2

# 3. Verify DynamoDB Global Table is active in secondary
aws dynamodb describe-table --table-name compliance-scan-jobs \
  --region us-west-2

# 4. Confirm Lambda functions exist in secondary
aws lambda list-functions --region us-west-2 \
  --query 'Functions[?starts_with(FunctionName, `compliance-check`)]'

# 5. ArgoCD in secondary auto-syncs from same Git repo
```

### Backup Strategy

- **DynamoDB**: Point-in-time recovery (PITR) enabled, retains 35 days
- **EKS etcd**: Managed by AWS — automatic backups every 3 hours
- **Lambda code**: Always in Git + ECR (immutable image tags)
- **Terraform state**: S3 versioning + DynamoDB locking + S3 Cross-Region Replication

---

## Security Architecture

```
NETWORK SECURITY:
  1. EKS API endpoint: private (VPC only) + limited public CIDR
  2. Lambda: runs in private subnets, NAT gateway for outbound
  3. Istio mTLS: STRICT mode in compliance namespace
  4. Istio AuthorizationPolicy: only istio-ingressgateway can call app pods
  5. SecurityGroup: Lambda SG allows only egress, no inbound

APPLICATION SECURITY:
  1. API Key authentication on all /api/v1 endpoints
  2. Non-root container (UID 1000), read-only root filesystem
  3. seccompProfile: RuntimeDefault dropped all capabilities
  4. PodDisruptionBudget: minimum 2 pods always running
  5. Secrets via Kubernetes Secrets (backed by AWS Secrets Manager via External Secrets Operator)

IAM SECURITY:
  1. IRSA (IAM Roles for Service Accounts): pods get dedicated IAM role, not node role
  2. Lambda role: minimal permissions per check (principle of least privilege)
  3. Cross-account access: STS AssumeRole with external ID
  4. KMS: DynamoDB, EBS, ECR all encrypted with customer-managed keys

SUPPLY CHAIN SECURITY:
  1. Kaniko: no Docker daemon, rootless build in Kubernetes
  2. Trivy: container image scanned on every build
  3. Bandit: SAST on Python code
  4. Safety: dependency vulnerability scan
  5. ECR scanning on push: continuous vulnerability detection
```

---

## Key Parameters & Configuration

### Critical Parameters to Tune

| Parameter | Default | Impact | When to Change |
|-----------|---------|--------|---------------|
| `MAX_CONCURRENT_LAMBDA_CALLS` | 20 | Lambda concurrency burst | Increase if accounts × regions × checks > 100 |
| `SCAN_TIMEOUT_SECONDS` | 300 | Max wait for all Lambda calls | Increase for large accounts (many stacks/buckets) |
| `HPA maxReplicas` | 20 | Max FastAPI pods | Increase for multi-tenant high-volume |
| `Lambda timeout` | 300s | Per-check execution limit | CFN drift detection takes ~60s per stack |
| `Lambda reserved_concurrent_executions` | 50 per function | Prevents Lambda throttle cascade | Tune per check frequency |
| `Map state MaxConcurrency` | N/A (uses semaphore) | Thread pool size | Aligned to Lambda account limits |
| `DynamoDB billing` | PAY_PER_REQUEST | Cost vs throughput | Switch to PROVISIONED above 10K WCU/day |
| `CANARY_WEIGHT` | 10 | % traffic to green during bake | Lower = safer, higher = faster validation |
| `CANARY_BAKE_SEC` | 300 | Seconds to observe canary | Corresponds to traffic volume for significance |
| `ERROR_THRESHOLD` | 1.0% | Max error rate before rollback | Adjust based on baseline noise |
| `PDB minAvailable` | 2 | Min pods during node drain | Always ≥ 1, recommended ≥ 2 for HA |

### IAM Cross-Account Role `ComplianceScannerRole`

Must be deployed to every target account with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::SCANNER_ACCOUNT:role/compliance-scanner-lambda-role"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "compliance-scanner-v1"
      }
    }
  }]
}
```

Managed policies: `SecurityAudit` + `ReadOnlyAccess`

---

## Local Development

### Prerequisites

```bash
# Install
brew install python@3.12 kubectl helm argocd eksctl aws-cli terraform

# Clone repo
git clone https://gitlab.company.com/platform/aws-compliance-scanner.git
cd aws-compliance-scanner
```

### Run FastAPI locally

```bash
cd fastapi-app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Set required env vars
export ENVIRONMENT=local
export SLOT=local
export AWS_REGION=us-east-1
export DYNAMODB_SCAN_TABLE=compliance-scan-results
export DYNAMODB_JOB_TABLE=compliance-scan-jobs
export API_KEYS='["dev-api-key"]'
export ENABLE_TRACING=false

# Start local DynamoDB (optional)
docker run -d -p 8000:8000 amazon/dynamodb-local

# Run app
python -m uvicorn app.main:app --reload --port 8080
```

### Test a scan locally

```bash
curl -X POST http://localhost:8080/api/v1/scan \
  -H "X-API-Key: dev-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "account_ids": ["123456789012"],
    "regions": ["us-east-1"],
    "checks": ["cfn_drift", "vpc_flow_logs"]
  }'
```

### Run tests

```bash
cd fastapi-app
pytest tests/ -v --tb=short
```

---

## Deployment Runbook

### First-time Infrastructure Setup

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Configure kubectl
aws eks update-kubeconfig --name compliance-scanner-cluster --region us-east-1

# Bootstrap ArgoCD
kubectl apply -f argocd/argocd-project.yaml
kubectl apply -f argocd/app-of-apps.yaml

# Get ArgoCD initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Deploy new version (via GitLab CI, automated)

1. Merge to `main` branch in GitLab
2. Pipeline triggers automatically:
   - Lint → Test → Build image → Security scan
   - Deploy to green slot → Canary 5min
   - Auto-promote or auto-rollback

### Manual Blue/Green cutover

```bash
# Route 10% to green
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":90},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":10}
  ]'

# Watch error rates in Grafana / CloudWatch

# Full cutover
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":0},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":100}
  ]'

# Immediate rollback
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":100},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":0}
  ]'
```

---

## Scenario-Based Interview Questions

### Scenario 1: Lambda throttling during peak scan

**Q**: A customer triggers a scan of 50 accounts × 5 regions × 15 checks = 3,750 Lambda invocations simultaneously. Lambda concurrent limit is 1,000. What happens and how do you handle it?

**A**:
- Without control: FastAPI would hit Lambda throttling (`TooManyRequestsException`), returning errors.
- Solution 1: **Semaphore in FastAPI** — `MAX_CONCURRENT_LAMBDA_CALLS=20` limits concurrent invocations per scan job. Multiple scan jobs still need Lambda reserved concurrency.
- Solution 2: **Reserved concurrency per Lambda** — `reserved_concurrent_executions=50` per function. 15 functions × 50 = 750 max concurrent, well within account limit.
- Solution 3: **SQS-backed queue** — Instead of direct Lambda.invoke, push each check to SQS. Lambda polls SQS with `batch_size=10`. This provides natural buffering and retry.
- Solution 4: **Async Lambda invocation** — Use `InvocationType=Event` (fire-and-forget). FastAPI stores job as PENDING. Each Lambda writes result directly to DynamoDB. Polling/WebSocket for results.
- **Best approach for production**: Semaphore + reserved concurrency + SQS for very large scans.

---

### Scenario 2: Blue/Green rollback too slow

**Q**: During a canary, you detect issues but the Istio `kubectl patch` rollback takes 3 seconds and 1% of requests to green see errors. How do you make rollback faster/safer?

**A**:
- Implement **Istio circuit breaking** via `DestinationRule.outlierDetection`: eject green after 3 consecutive 5xx.
- The DR already has `consecutiveGatewayErrors: 3, baseEjectionTime: 60s` — this is **automatic** without CI intervention.
- Use **Argo Rollouts** (instead of manual VirtualService patching) — provides `blueGreen.autoPromotionEnabled=false`, built-in metric analysis, and automatic rollback.
- Set green initial weight to 5% not 10% for less blast radius.
- Pre-warm green pods with readiness probe before adding to VirtualService.

---

### Scenario 3: Cross-account scan fails with AccessDenied

**Q**: Scanning account B from account A fails. Account B's `ComplianceScannerRole` exists but STS.AssumeRole returns AccessDenied. Why?

**A**: Possible causes:
1. **Trust policy mismatch** — Lambda role ARN in trust policy doesn't match actual Lambda role ARN (wrong account ID, wrong role name).
2. **Permission boundary** — Lambda execution role has a permission boundary that blocks `sts:AssumeRole`.
3. **SCP (Service Control Policy)** — AWS Organization SCP in account B denies `sts:AssumeRole` for external principals.
4. **Condition mismatch** — Trust policy has `sts:ExternalId` condition but Lambda isn't sending the external ID.
5. **Session duration** — Assumed role credentials expired mid-scan for long-running Lambda.
- Debug: `aws sts assume-role --role-arn <arn> --role-session-name test` from within the VPC. Check CloudTrail `AssumeRole` events in account B.

---

### Scenario 4: ArgoCD self-heal causing deployment loops

**Q**: The HPA scales down pods from 5 to 3, but ArgoCD's `selfHeal=true` sees the deployment `spec.replicas` as out-of-sync (ArgoCD expects 3 from git, k8s has 3 from HPA which is correct). It keeps trying to sync. How do you fix?

**A**:
- This is a classic ArgoCD + HPA conflict.
- Fix: Add `ignoreDifferences` in the ArgoCD Application manifest for `/spec/replicas`:
  ```yaml
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
  ```
- This is already present in our `application-blue.yaml` and `application-green.yaml`.
- Additionally, remove `replicas` from the base `deployment.yaml` and let HPA manage it entirely.

---

### Scenario 5: DynamoDB hot partition causing throttling

**Q**: Scans from a large enterprise customer always use the same 5 account IDs. The GSI `account-status-index` is getting throttled. Fix?

**A**:
- The issue is a **hot key** — the same `account_id` values being written repeatedly.
- Solution 1: **Add a random suffix to the partition key** (e.g., `account_id|${random(0,9)}`), query all 10 partitions and aggregate.
- Solution 2: **Switch to `PAY_PER_REQUEST`** — already implemented. DynamoDB auto-scales, no manual provisioning.
- Solution 3: **DynamoDB Accelerator (DAX)** — caching layer for read-heavy workloads.
- Solution 4: **Compress or archive old results** — TTL records older than 90 days to S3, reducing table size.
- Solution 5: **Write sharding** — write results per-check (already using `check_id` as range key — this distributes writes).

---

### Scenario 6: Istio mTLS breaking Lambda-to-DynamoDB calls

**Q**: After enabling `STRICT` mTLS in the compliance namespace, Lambda invocations from the FastAPI pod succeed, but DynamoDB writes from the pod fail. Why?

**A**:
- Istio mTLS applies to **east-west service-to-service** traffic inside the mesh (pod-to-pod).
- DynamoDB is an **AWS managed service outside the mesh** — traffic exits via the VPC endpoint or NAT gateway.
- This is not affected by PeerAuthentication mTLS.
- The actual issue if DynamoDB calls fail after mTLS is likely an **IAM / IRSA configuration problem** — the pod's service account token is not being exchanged for the IAM role credentials properly.
- Debug: `kubectl exec <pod> -- curl http://169.254.169.254/latest/meta-data/` to check IRSA is working, or `aws sts get-caller-identity` from inside the pod.

---

### Scenario 7: Green deployment not getting picked up by ArgoCD

**Q**: CI pipeline changed `k8s/overlays/green/kustomization.yaml` and pushed to `main`. But ArgoCD still shows the old image. Why?

**A**: Possible causes:
1. **Webhook not configured** — ArgoCD polls Git every 3 minutes by default. Configure a GitLab webhook to ArgoCD server for immediate notification.
2. **Git credential issue** — ArgoCD repo credentials expired or incorrect. Check `argocd repo list`.
3. **Image not in ECR** — If the new image tag referenced in kustomization doesn't exist in ECR yet, ArgoCD sync succeeds but EKS can't pull the image → `ImagePullBackOff`. Check with `kubectl describe pod`.
4. **Kustomize cache** — ArgoCD has a kustomize render cache. Force refresh: `argocd app get compliance-scanner-green --refresh`.
5. **ignoreDifferences** — If we misconfigured it to ignore the image field, ArgoCD won't see it as different.
- Fix: `argocd app sync compliance-scanner-green --force`

---

### Scenario 8: Compliance scan takes 45 minutes for large accounts

**Q**: A customer with 500 CloudFormation stacks, 100 VPCs, and 3 regions takes 45 minutes. How do you optimize?

**A**:
1. **Increase `MAX_CONCURRENT_LAMBDA_CALLS`** from 20 to 100 (ensure Lambda concurrency limit accommodates).
2. **Per-check parallelism inside Lambda** — `cfn-drift-check` currently polls stacks sequentially. Use `concurrent.futures.ThreadPoolExecutor` inside the Lambda to detect drift on multiple stacks simultaneously.
3. **Express Workflow via Step Functions** — Convert the fan-out to a Map state in an Express Workflow for better visibility and built-in retry.
4. **Pagination optimization** — Use DynamoDB BatchWriteItem (up to 25 items) for writing results instead of individual PutItem calls.
5. **Lambda provisioned concurrency** — Pre-warm Lambdas to avoid cold starts (each cold start = ~500ms).
6. **Async scan model** — Already implemented (202 Accepted + polling). The 45-minute scan is background; clients just poll.
7. **EventBridge-driven scans** — Split the large scan into per-account mini-scans, each triggered via EventBridge. Parallel sub-jobs.

---

### Scenario 9: How do you handle a new compliance check being added without downtime?

**A**:
1. Add the new Lambda function directory under `lambda-functions/new-check/handler.py`.
2. Register it in `REGISTERED_CHECKS` in `lambda_invoker.py`.
3. Add it to the `lambda_checks` list in `terraform/lambda.tf`.
4. CI pipeline: build + deploy Lambda (via `aws lambda update-function-code`).
5. FastAPI: the new check is included in the default checks list. Old scan jobs that ran before the check was added won't include it (job stores which checks were run).
6. **Zero downtime** because:
   - Lambda is deployed independently before the FastAPI code references it.
   - The check is added to `REGISTERED_CHECKS` in the FastAPI code update.
   - FastAPI blue/green deploy means old blue continues to run without the new check while green (with new check) is validated.
   - Optional: feature flag → only run new check if `checks` array explicitly includes it during initial rollout.

---

### Scenario 10: Multi-tenant isolation — Customer A shouldn't see Customer B's results

**Q**: The API is shared infrastructure. How do you ensure tenant isolation?

**A**:
1. **API Key → Account binding** — Each API key is scoped to a set of `allowed_account_ids`. FastAPI validates: `if account_id not in allowed_accounts_for_api_key: raise 403`.
2. **DynamoDB access pattern** — Scan results are partitioned by `job_id`. Job IDs are UUIDs not guessable. Clients only know their own job IDs.
3. **Separate namespaces / clusters** — For strict isolation, deploy a separate compliance-scanner pod (or even cluster) per large enterprise tenant.
4. **Data encryption** — DynamoDB KMS encryption ensures even AWS support can't read another tenant's data without the key.
5. **Audit logging** — All API calls logged with `account_id` in CloudWatch. Any cross-tenant access attempt produces an alert.
