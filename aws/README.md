# AWS Senior DevOps Engineer Interview Preparation

Comprehensive AWS interview guide covering architecture patterns, services, and real-world scenarios.

---

## 📁 Repository Structure

```
aws/
├── README.md                              # This file
├── 01-THREE-TIER-ARCHITECTURE.md          # 3-tier design patterns
├── 02-NETWORKING.md                       # VPC, subnets, security groups
├── 03-ECS.md                              # Container orchestration
├── 04-LAMBDA.md                           # Serverless compute
├── 05-STEP-FUNCTIONS.md                   # Workflow orchestration
├── 06-SECURITY.md                         # IAM, encryption, compliance
├── 07-HIGH-AVAILABILITY.md                # Multi-AZ, auto-scaling
├── 08-DISASTER-RECOVERY.md                # DR strategies, RTO/RPO
├── 09-MONITORING-ALERTING.md              # CloudWatch, alerts
├── 10-SERVICE-SELECTION-GUIDE.md          # When to use what
├── 11-DEBUGGING-TROUBLESHOOTING.md        # Production debugging
└── 12-SCENARIO-QUESTIONS.md               # Interview scenarios
```

---

## 🎯 Quick Reference: AWS Services Overview

| Category | Services | Use Case |
|----------|----------|----------|
| **Compute** | EC2, ECS, EKS, Lambda, Fargate | Application workloads |
| **Storage** | S3, EBS, EFS, FSx | Data persistence |
| **Database** | RDS, DynamoDB, Aurora, ElastiCache | Data management |
| **Networking** | VPC, ALB, NLB, CloudFront, Route53 | Traffic management |
| **Security** | IAM, KMS, Secrets Manager, GuardDuty | Protection |
| **Monitoring** | CloudWatch, X-Ray, CloudTrail | Observability |
| **Integration** | SQS, SNS, EventBridge, Step Functions | Decoupling |

---

## 🏗️ Core Architecture Patterns

### 1. Three-Tier Architecture
```
Internet → CloudFront → ALB → Web Tier → App Tier → Data Tier
```

### 2. Serverless Architecture
```
API Gateway → Lambda → DynamoDB/Aurora Serverless
```

### 3. Event-Driven Architecture
```
EventBridge → Lambda/Step Functions → Multiple Targets
```

### 4. Microservices Architecture
```
ALB → ECS/EKS Services → Service Mesh → Databases
```

---

## 📊 Key Metrics to Know

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| API Latency (p99) | < 200ms | 200-500ms | > 500ms |
| Error Rate | < 0.1% | 0.1-1% | > 1% |
| CPU Utilization | < 60% | 60-80% | > 80% |
| Memory Utilization | < 70% | 70-85% | > 85% |
| DB Connections | < 70% max | 70-90% | > 90% |

---

## 🔑 Interview Topics Quick Links

1. [Three-Tier Architecture](01-THREE-TIER-ARCHITECTURE.md) - Design principles, scaling strategies
2. [Networking Deep Dive](02-NETWORKING.md) - VPC design, security groups, NACLs
3. [ECS Mastery](03-ECS.md) - Task definitions, services, capacity providers
4. [Lambda Best Practices](04-LAMBDA.md) - Cold starts, concurrency, patterns
5. [Step Functions](05-STEP-FUNCTIONS.md) - Workflow orchestration, error handling
6. [Security](06-SECURITY.md) - IAM, encryption, compliance
7. [High Availability](07-HIGH-AVAILABILITY.md) - Multi-AZ, auto-scaling, failover
8. [Disaster Recovery](08-DISASTER-RECOVERY.md) - Strategies, RTO/RPO planning
9. [Monitoring & Alerting](09-MONITORING-ALERTING.md) - CloudWatch, dashboards, alerts
10. [Service Selection](10-SERVICE-SELECTION-GUIDE.md) - Decision trees
11. [Debugging](11-DEBUGGING-TROUBLESHOOTING.md) - Production troubleshooting
12. [Scenario Questions](12-SCENARIO-QUESTIONS.md) - Interview practice

---

## 🚀 Quick Start Study Plan

### Week 1: Foundations
- Day 1-2: Networking (VPC, subnets, security)
- Day 3-4: Compute (EC2, ECS, Lambda)
- Day 5-7: Storage & Databases

### Week 2: Advanced Topics
- Day 1-2: High Availability & DR
- Day 3-4: Security & IAM
- Day 5-7: Monitoring & Debugging

### Week 3: Practice
- Day 1-3: Scenario-based questions
- Day 4-5: System design practice
- Day 6-7: Mock interviews

---

## 💡 Tips for Success

1. **Know the "Why"**: Don't just know services, understand when to use them
2. **Think in Trade-offs**: Every decision has pros and cons
3. **Cost Awareness**: Always consider cost implications
4. **Security First**: Embed security in every design
5. **Practice Diagrams**: Draw architectures clearly
6. **Real Experience**: Relate answers to your actual experience

---

*Good luck with your AWS interview!*
