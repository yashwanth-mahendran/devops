# Operational Runbook: AWS Compliance Scanner

## Table of Contents

1. [Incident Response](#incident-response)
2. [Blue/Green Manual Operations](#bluegreen-manual-operations)
3. [Scaling Procedures](#scaling-procedures)
4. [Database Operations](#database-operations)
5. [Lambda Operations](#lambda-operations)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Disaster Recovery Procedures](#disaster-recovery-procedures)
8. [Common Troubleshooting](#common-troubleshooting)

---

## Incident Response

### P1: API Down (all requests returning 5xx)

```bash
# 1. Check pod status
kubectl get pods -n compliance -l app=compliance-scanner

# 2. Check recent events
kubectl get events -n compliance --sort-by='.lastTimestamp' | tail -20

# 3. Check logs
kubectl logs -n compliance -l app=compliance-scanner --since=10m

# 4. Check Istio proxy
kubectl logs -n compliance <pod-name> -c istio-proxy | tail -50

# 5. Check HPA (auto-scaling might be failing)
kubectl describe hpa -n compliance

# 6. Immediate rollback if new deployment is bad
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[{"op":"replace","path":"/spec/http/1/route/0/weight","value":100},
                   {"op":"replace","path":"/spec/http/1/route/1/weight","value":0}]'

# 7. Check if it's an Istio issue
kubectl get pods -n istio-system
istioctl proxy-status
```

### P2: High Latency (p99 > 10s)

```bash
# 1. Check database latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name SuccessfulRequestLatency \
  --dimensions Name=TableName,Value=compliance-scan-jobs \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics p99

# 2. Check Lambda latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=compliance-check-cfn-drift \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics p99

# 3. Check if HPA has scaled down too aggressively
kubectl get hpa -n compliance

# 4. Check Istio circuit breaker trips in Grafana
# Dashboard: "Istio Service Mesh" → "Outlier Detection Events"

# 5. Temporarily increase pod count manually
kubectl scale deployment compliance-scanner-blue -n compliance --replicas=10
```

### P3: Scan Jobs Stuck in RUNNING State

```bash
# Find jobs stuck for > 15 minutes
aws dynamodb scan \
  --table-name compliance-scan-jobs \
  --filter-expression "#s = :running AND created_at < :threshold" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":running":{"S":"RUNNING"}, ":threshold":{"S":"2024-01-01T00:00:00Z"}}'

# Check Lambda for throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value=compliance-check-cfn-drift \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum

# Force-complete stuck jobs (use /rescan endpoint or update DynamoDB directly)
aws dynamodb update-item \
  --table-name compliance-scan-jobs \
  --key '{"job_id": {"S": "<job_id>"}}' \
  --update-expression "SET #s = :failed, updated_at = :now" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":failed":{"S":"FAILED"}, ":now":{"S":"2024-01-01T00:00:00Z"}}'
```

---

## Blue/Green Manual Operations

### Check Current Traffic Split

```bash
kubectl get virtualservice compliance-scanner-vs -n compliance -o yaml | \
  grep -A 20 "route:"
```

### Gradually Shift Traffic to Green

```bash
# Step 1: 10% canary
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":90},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":10}
  ]'

# Watch error rates for 5 minutes
kubectl top pods -n compliance
# Check Grafana: "Blue/Green Status" dashboard

# Step 2: 50/50
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":50},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":50}
  ]'

# Step 3: Full green
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":0},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":100}
  ]'
```

### Emergency Rollback (instant)

```bash
kubectl patch virtualservice compliance-scanner-vs -n compliance \
  --type=json -p='[
    {"op":"replace","path":"/spec/http/1/route/0/weight","value":100},
    {"op":"replace","path":"/spec/http/1/route/1/weight","value":0}
  ]'
echo "Traffic fully on BLUE — rollback complete"
```

---

## Scaling Procedures

### Manual Scale-Up (e.g., ahead of scheduled scans)

```bash
# Scale blue deployment
kubectl scale deployment compliance-scanner-blue -n compliance --replicas=10

# Verify all pods are Running
kubectl rollout status deployment/compliance-scanner-blue -n compliance

# Scale back down (let HPA manage)
kubectl scale deployment compliance-scanner-blue -n compliance --replicas=0
# Remove manual override — HPA takes over
kubectl patch deployment compliance-scanner-blue -n compliance \
  --subresource scale \
  --type=merge \
  -p '{"spec": {"replicas": null}}'
```

### Increase Lambda Concurrency

```bash
# Increase reserved concurrency for a specific check
aws lambda put-function-concurrency \
  --function-name compliance-check-cfn-drift \
  --reserved-concurrent-executions 100

# Or set to unreserved (uses account limit)
aws lambda delete-function-concurrency \
  --function-name compliance-check-cfn-drift
```

---

## Database Operations

### Check DynamoDB Table Health

```bash
# Describe table
aws dynamodb describe-table --table-name compliance-scan-jobs

# Check consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=compliance-scan-jobs \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum
```

### Restore DynamoDB from PITR

```bash
# List available PITR restore times
aws dynamodb describe-continuous-backups \
  --table-name compliance-scan-jobs

# Restore to a specific point in time (creates a NEW table)
aws dynamodb restore-table-to-point-in-time \
  --source-table-name compliance-scan-jobs \
  --target-table-name compliance-scan-jobs-restored \
  --restore-date-time "2024-01-15T12:00:00Z"

# Wait for restore to complete
aws dynamodb wait table-exists --table-name compliance-scan-jobs-restored

# Verify data then update application config to point to new table
# (or use DynamoDB Streams to reconcile)
```

### Archive Old Scan Results

```bash
# Export to S3 (requires PITR enabled — it is)
aws dynamodb export-table-to-point-in-time \
  --table-arn arn:aws:dynamodb:us-east-1:123456789012:table/compliance-scan-results \
  --s3-bucket compliance-scanner-archive \
  --s3-prefix "exports/$(date +%Y-%m)" \
  --export-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --export-format DYNAMODB_JSON

# Then delete old items (write a cleanup Lambda or use TTL)
# Items older than 90 days can be auto-expired by setting TTL attribute
```

---

## Lambda Operations

### Deploy Single Lambda (without full pipeline)

```bash
FUNCTION_NAME="compliance-check-cfn-drift"
REGION="us-east-1"

# Package
cd lambda-functions/cfn-drift-check
zip -r /tmp/${FUNCTION_NAME}.zip handler.py

# Deploy
aws lambda update-function-code \
  --function-name ${FUNCTION_NAME} \
  --zip-file fileb:///tmp/${FUNCTION_NAME}.zip \
  --region ${REGION}

# Wait for update
aws lambda wait function-updated \
  --function-name ${FUNCTION_NAME} \
  --region ${REGION}

# Publish version
VERSION=$(aws lambda publish-version \
  --function-name ${FUNCTION_NAME} \
  --region ${REGION} \
  --query 'Version' --output text)

# Update :live alias
aws lambda update-alias \
  --function-name ${FUNCTION_NAME} \
  --name live \
  --function-version ${VERSION} \
  --region ${REGION}

echo "Deployed ${FUNCTION_NAME} version ${VERSION} to :live alias"
```

### Test a Lambda Function Manually

```bash
aws lambda invoke \
  --function-name compliance-check-cfn-drift \
  --qualifier live \
  --payload '{"account_id":"123456789012","region":"us-east-1"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json && cat /tmp/response.json | python3 -m json.tool
```

### Check Lambda Logs

```bash
# Tail logs for a function
aws logs tail /aws/lambda/compliance-check-cfn-drift --follow

# Search for errors in last hour
aws logs filter-log-events \
  --log-group-name /aws/lambda/compliance-check-cfn-drift \
  --start-time $(python3 -c "import time; print(int((time.time()-3600)*1000))") \
  --filter-pattern "ERROR"
```

---

## Monitoring & Alerting

### Key Grafana Dashboards

| Dashboard | URL |
|-----------|-----|
| API Performance | http://grafana.monitoring.svc/d/api-perf |
| Blue/Green Status | http://grafana.monitoring.svc/d/bluegreen |
| Lambda Performance | http://grafana.monitoring.svc/d/lambda |
| EKS Cluster | http://grafana.monitoring.svc/d/eks |
| Compliance Overview | http://grafana.monitoring.svc/d/compliance |

### Silencing a Misfiring Alert

```bash
# Via Alertmanager API
curl -XPOST http://alertmanager.monitoring.svc:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "alertname", "value": "ComplianceScannerHighErrorRate"}],
    "startsAt": "2024-01-15T12:00:00Z",
    "endsAt": "2024-01-15T14:00:00Z",
    "comment": "Investigating — @oncall",
    "createdBy": "operator"
  }'
```

---

## Disaster Recovery Procedures

### Failover to us-west-2 (P1 incident, primary region down)

```bash
# 1. Verify DynamoDB Global Table is in sync
aws dynamodb describe-table \
  --table-name compliance-scan-jobs \
  --region us-west-2 \
  --query 'Table.TableStatus'

# 2. Scale up EKS in secondary region
kubectl scale deployment compliance-scanner-blue -n compliance \
  --replicas=3 --context=arn:aws:eks:us-west-2:123456789012:cluster/compliance-scanner-cluster-dr

# 3. Verify Lambda functions exist in us-west-2
aws lambda list-functions --region us-west-2 \
  --query 'Functions[?starts_with(FunctionName, `compliance-check`)].FunctionName'

# 4. Route 53 health check should auto-failover
# Manual override if needed:
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "compliance-scanner.company.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<us-west-2-alb-zone>",
          "DNSName": "<us-west-2-alb-dns>",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# 5. Verify health in secondary
curl https://compliance-scanner.company.com/healthz
curl https://compliance-scanner.company.com/readyz
```

---

## Common Troubleshooting

### Pod CrashLoopBackOff

```bash
kubectl describe pod <pod-name> -n compliance
kubectl logs <pod-name> -n compliance --previous
# Check securityContext: readOnlyRootFilesystem requires tmpfs for any writes
# Check IRSA: verify service account annotation and OIDC provider
```

### IRSA Not Working (403 from AWS SDK)

```bash
# Inside the failing pod
kubectl exec -it <pod-name> -n compliance -- sh
env | grep AWS
# Should see: AWS_WEB_IDENTITY_TOKEN_FILE, AWS_ROLE_ARN

# Test token exchange
cat $AWS_WEB_IDENTITY_TOKEN_FILE | python3 -c "import sys,jwt; print(jwt.decode(sys.stdin.read(), options={'verify_signature':False}))"
# Should show sub: system:serviceaccount:compliance:compliance-scanner

# Test assume role
aws sts assume-role-with-web-identity \
  --role-arn $AWS_ROLE_ARN \
  --role-session-name test \
  --web-identity-token $(cat $AWS_WEB_IDENTITY_TOKEN_FILE)
```

### ArgoCD App Out-of-Sync

```bash
argocd app get compliance-scanner-blue
argocd app diff compliance-scanner-blue
argocd app sync compliance-scanner-blue --force

# If stuck in "Sync Failed"
argocd app terminate-op compliance-scanner-blue
argocd app sync compliance-scanner-blue
```

### Istio Sidecar Injection Not Working

```bash
# Verify namespace label
kubectl get namespace compliance --show-labels
# Should show: istio-injection=enabled

# Verify istiod is healthy
kubectl get pods -n istio-system -l app=istiod

# Check injection webhook
kubectl get mutatingwebhookconfigurations istio-sidecar-injector

# Re-roll pods to trigger injection
kubectl rollout restart deployment compliance-scanner-blue -n compliance
```
