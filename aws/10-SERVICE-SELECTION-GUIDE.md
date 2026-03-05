# AWS Service Selection Guide

When to use which AWS service - decision trees and recommendations for senior DevOps engineers.

---

## Table of Contents

1. [Compute Service Selection](#compute-service-selection)
2. [Container Orchestration](#container-orchestration)
3. [Database Selection](#database-selection)
4. [Messaging and Queuing](#messaging-and-queuing)
5. [Storage Selection](#storage-selection)
6. [Networking Selection](#networking-selection)
7. [Serverless vs Containers](#serverless-vs-containers)
8. [Interview Questions](#interview-questions)

---

## Compute Service Selection

### Decision Tree

```
                           START: What type of workload?
                                      │
           ┌──────────────────────────┼──────────────────────────┐
           │                          │                          │
           ▼                          ▼                          ▼
      Containers               Serverless/Events            VMs/Bare Metal
           │                          │                          │
           │                          │                          │
    ┌──────┴──────┐           ┌───────┴───────┐                 │
    │             │           │               │                 │
    ▼             ▼           ▼               ▼                 ▼
Need K8s?   Simple deploy   < 15 min      Async/Queue       EC2
    │             │           │               │                 │
    │             │           │               │          ┌──────┴──────┐
    ▼             ▼           ▼               ▼          │             │
   YES           NO        Lambda          Lambda    Predictable   Burstable
    │             │           │               │      workload      workload
    │             │           │               │          │             │
    ▼             ▼           ▼               ▼          ▼             ▼
  EKS         ECS/Fargate   Lambda         SQS       Reserved     Spot/On-demand
                            + API GW       + Lambda   + Savings
                                                       Plans
```

### Compute Comparison

| Service | Best For | Avoid When |
|---------|----------|------------|
| **Lambda** | Event-driven, variable load, < 15min | Long-running, consistent load, GPU |
| **ECS Fargate** | Containers without infra mgmt | Cost optimization, GPU |
| **ECS EC2** | Cost optimization, custom AMIs | Simple workloads |
| **EKS** | K8s expertise, multi-cloud | Small teams, simple apps |
| **EC2** | Full control, specialized hardware | Operational overhead concern |
| **App Runner** | Simple container deployment | Complex networking |

---

## Container Orchestration

### ECS vs EKS Decision

```
                    Container Orchestration
                            │
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
         Need Kubernetes?           AWS-native OK?
              │                           │
         ┌────┴────┐                ┌────┴────┐
         │         │                │         │
         ▼         ▼                ▼         ▼
        YES        NO              YES        NO
         │         │                │         │
         │         │                │         │
         ▼         ▼                ▼         ▼
        EKS   ─────┼───────────▶   ECS      EKS
                   │
                   │
              ┌────┴────┐
              │         │
              ▼         ▼
         Need EC2?   Serverless OK?
              │         │
              ▼         ▼
         ECS EC2    ECS Fargate
```

### Detailed Comparison

| Factor | ECS Fargate | ECS EC2 | EKS |
|--------|-------------|---------|-----|
| **Learning Curve** | Low | Medium | High |
| **Operational Overhead** | Minimal | Medium | High |
| **Cost (small scale)** | Higher | Lower | Higher |
| **Cost (large scale)** | Medium | Lower | Medium |
| **Flexibility** | Limited | High | Highest |
| **Multi-cloud** | No | No | Yes |
| **GPU Support** | No | Yes | Yes |

### When to Choose What

**Choose ECS Fargate when:**
- Team lacks container infrastructure experience
- Variable, unpredictable workloads
- Want minimal operational overhead
- No GPU requirements

**Choose ECS EC2 when:**
- Need cost optimization at scale
- Require GPU instances
- Need custom AMIs or host-level access
- Stable, predictable workloads

**Choose EKS when:**
- Team has Kubernetes expertise
- Multi-cloud or hybrid strategy
- Need advanced K8s features (custom controllers, service mesh)
- Using K8s-native tools (Helm, ArgoCD, Istio)

---

## Database Selection

### Decision Tree

```
                         What type of data?
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
      Relational          Key-Value/Doc          Time-series
         │                     │                     │
    ┌────┴────┐          ┌────┴────┐                │
    │         │          │         │                │
    ▼         ▼          ▼         ▼                ▼
 Need      Simple    Low latency  Document      Timestream
 scaling?  workload  caching?     store?            │
    │         │          │         │                │
    ▼         ▼          ▼         ▼           IoT/Metrics
  ┌─┴─┐    RDS        Redis     DynamoDB
  │   │               (Cache)
YES  NO
  │   │
  ▼   ▼
Aurora RDS


                Graph Data?              Search?
                    │                       │
                    ▼                       ▼
                Neptune              OpenSearch
```

### Database Comparison

| Database | Use Case | Scale | Consistency |
|----------|----------|-------|-------------|
| **RDS PostgreSQL** | Traditional apps, complex queries | Vertical (+ read replicas) | Strong |
| **Aurora** | High availability, auto-scaling | Horizontal reads | Strong |
| **DynamoDB** | Key-value, unlimited scale | Horizontal | Eventually/Strong |
| **ElastiCache Redis** | Caching, sessions | Cluster | Configurable |
| **DocumentDB** | MongoDB-compatible | Cluster | Strong |
| **Neptune** | Graph relationships | Cluster | Strong |
| **OpenSearch** | Full-text search, logs | Cluster | Eventually |
| **Timestream** | Time-series, IoT | Serverless | Eventually |

### SQL vs NoSQL Decision

**Choose SQL (RDS/Aurora) when:**
- Complex queries with JOINs
- ACID transactions required
- Relational data model
- Existing SQL expertise

**Choose DynamoDB when:**
- Simple key-value access patterns
- Massive scale requirements
- Predictable, low latency
- Flexible schema

---

## Messaging and Queuing

### Decision Tree

```
                      Messaging Requirement
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   Point-to-point        Pub/Sub              Event Bus
   (Queue)               (Fan-out)            (Rule-based)
        │                     │                     │
        │                     │                     │
   ┌────┴────┐           ┌────┴────┐               │
   │         │           │         │               │
   ▼         ▼           ▼         ▼               ▼
Standard  Need FIFO?   Simple   Kinesis?      EventBridge
 queue?      │        fan-out   (streaming)
   │         │           │         │
   ▼         ▼           ▼         │
  SQS    SQS FIFO       SNS       │
Standard    │           │     ┌───┴───┐
   │        │           │     │       │
   └────────┴───────────┴─────┘       │
                                      ▼
                              High-throughput
                              streaming?
                                   │
                                   ▼
                                Kinesis
```

### Service Comparison

| Service | Use Case | Throughput | Ordering |
|---------|----------|------------|----------|
| **SQS Standard** | Decoupling, async | Unlimited | Best-effort |
| **SQS FIFO** | Ordered processing | 3,000 msg/sec | Guaranteed |
| **SNS** | Fan-out, notifications | Unlimited | No guarantee |
| **Kinesis Data Streams** | Real-time streaming | Per shard | Per shard |
| **EventBridge** | Event routing, SaaS | 10,000 events/sec | No guarantee |
| **MSK (Kafka)** | High-throughput streaming | Very high | Per partition |

### When to Choose What

**SQS vs Kinesis:**
```
SQS:                               Kinesis:
- Delete after processing         - Multiple consumers same data
- Simple queue operations         - Real-time analytics
- At-least-once OK               - Replay capability needed
- Variable throughput             - Per-record ordering needed
```

---

## Storage Selection

### Decision Tree

```
                        Storage Type?
                             │
       ┌─────────────────────┼─────────────────────┐
       │                     │                     │
       ▼                     ▼                     ▼
   Object Storage      Block Storage         File Storage
       │                     │                     │
       ▼                     ▼                     ▼
      S3                   EBS                  EFS/FSx
       │                     │                     │
  ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
  │         │          │         │          │         │
  ▼         ▼          ▼         ▼          ▼         ▼
Frequent  Infrequent  High IOPS  Throughput Linux   Windows
access    access                             NFS     SMB
  │         │          │         │          │         │
  ▼         ▼          ▼         ▼          ▼         ▼
S3 Std   S3 IA/     gp3/io2   st1/sc1    EFS     FSx Windows
         Glacier
```

### Storage Comparison

| Storage | Use Case | Access | Cost |
|---------|----------|--------|------|
| **S3 Standard** | Frequently accessed objects | HTTP | $0.023/GB |
| **S3 IA** | Infrequent access | HTTP | $0.0125/GB |
| **S3 Glacier** | Archive | Hours to retrieve | $0.004/GB |
| **EBS gp3** | General purpose SSD | Block | $0.08/GB |
| **EBS io2** | High IOPS | Block | $0.125/GB |
| **EFS** | Shared Linux file system | NFS | $0.30/GB |
| **FSx Lustre** | HPC, ML | Parallel | $0.14/GB |

---

## Networking Selection

### Load Balancer Decision

```
                    Load Balancing Need
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
        HTTP/S          TCP/UDP       Internal only
           │               │               │
           │               │               │
    ┌──────┴──────┐       │         ┌─────┴─────┐
    │             │       │         │           │
    ▼             ▼       ▼         ▼           ▼
Need path     Simple    NLB      Internal    VPC Endpoint
routing?      HTTPS?              ALB/NLB    (PrivateLink)
    │             │
    ▼             ▼
   ALB          ALB
```

### Load Balancer Comparison

| Feature | ALB | NLB | GWLB |
|---------|-----|-----|------|
| **Protocol** | HTTP/HTTPS | TCP/UDP/TLS | IP |
| **Routing** | Path, host, header | Port | N/A |
| **Performance** | Good | Ultra-low latency | High |
| **Use Case** | Web apps | Gaming, IoT | Security appliances |
| **WebSocket** | Yes | Yes | No |
| **Static IP** | No (use Global Accelerator) | Yes | Yes |

---

## Serverless vs Containers

### Decision Matrix

```
                        Serverless vs Containers
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
        Execution Time    Load Pattern    Cost Priority
              │                │                │
         ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
         │         │      │         │      │         │
         ▼         ▼      ▼         ▼      ▼         ▼
       < 15min  > 15min  Variable  Steady  Pay-per-  Reserved
         │         │      │         │      use         │
         ▼         ▼      ▼         ▼      │           ▼
      Lambda   Containers Lambda  Containers │      Containers
                           │         │       │
                           └────────┬┴───────┘
                                    │
                                    ▼
                           Lambda Provisioned
                           Concurrency (steady load,
                           serverless benefits)
```

### Comparison Table

| Factor | Lambda | Fargate | ECS EC2 |
|--------|--------|---------|---------|
| **Startup Time** | Cold start (100ms-10s) | 30-60s | 30-60s |
| **Max Duration** | 15 min | Unlimited | Unlimited |
| **Pricing Model** | Per invocation | Per vCPU/memory/hour | Per EC2 instance |
| **Min Cost** | $0 (free tier) | ~$0.04/hour | ~$0.01/hour |
| **Scaling Speed** | Instant | 30-60s | Minutes |
| **Max Concurrency** | 1000 (default) | By task | By capacity |

### Cost Comparison (1M requests/month, 200ms each)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| **Lambda** | 128MB | ~$2 |
| **Lambda** | 512MB | ~$8 |
| **Fargate** | 0.25 vCPU, 0.5GB, always on | ~$30 |
| **ECS EC2** | t3.micro, always on | ~$8 |

---

## Interview Questions

### Q1: A startup has a web app with unpredictable traffic (0-10,000 requests/second). Which compute would you recommend?

**Answer:**

**Recommended: API Gateway + Lambda + DynamoDB**

**Reasoning:**
1. **Unpredictable traffic:** Lambda scales to zero and up instantly
2. **Startup:** Minimize ops overhead, pay-per-use
3. **Cost efficiency:** No idle costs during low traffic
4. **DynamoDB:** Handles unpredictable load with on-demand mode

**Architecture:**
```
CloudFront → API Gateway → Lambda → DynamoDB
                              │
                              ├──▶ S3 (static assets)
                              └──▶ ElastiCache (optional caching)
```

**When to migrate to containers:**
- Consistent high load (break-even ~40% utilization)
- Need execution > 15 minutes
- Cold starts become problematic

---

### Q2: Company has a PostgreSQL database reaching capacity limits. What are the options?

**Answer:**

**Evaluation order:**

1. **Optimize first:**
   - Query optimization, indexes
   - Connection pooling (RDS Proxy)
   - Read replicas for read-heavy workloads

2. **Vertical scaling:**
   - Upgrade instance size (quick fix)
   - Limited by largest instance available

3. **Aurora PostgreSQL:**
   - Up to 15 read replicas
   - Auto-scaling storage
   - Better HA built-in
   - Migration: Use DMS

4. **Horizontal partitioning:**
   - Citus (PostgreSQL extension)
   - Application-level sharding

5. **Consider DynamoDB:**
   - If access patterns allow
   - Single-digit millisecond latency at any scale
   - Requires application changes

**Decision tree:**
```
Can you optimize queries?
  → YES: Do it first
  → NO: Continue

Is it read-heavy?
  → YES: Add read replicas
  → NO: Continue

Need > current instance size?
  → YES: Consider Aurora or sharding
  → NO: Upgrade instance
```

---

### Q3: When would you use Kinesis over SQS?

**Answer:**

| Choose Kinesis | Choose SQS |
|----------------|------------|
| Multiple consumers for same data | Single consumer per message |
| Need to replay data | Delete after processing OK |
| Real-time analytics | Simple decoupling |
| Ordered events important | Order not critical |
| High throughput (> 10K/sec) | Variable throughput |
| Stream processing (Flink, Spark) | Simple Lambda triggers |
| 7-day retention needed | 14-day retention OK |

**Example scenarios:**

**Use Kinesis:**
- Real-time dashboard: Multiple consumers (alerts, analytics, archival)
- Click stream analysis: High volume, ordered, multiple consumers
- IoT sensor data: Time-ordered, analytics pipeline

**Use SQS:**
- Task queue: Workers process and delete tasks
- Email queue: Order doesn't matter, simple processing
- Async API: Decouple web tier from processing
