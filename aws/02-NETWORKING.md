# AWS Networking Deep Dive

Complete guide to VPC networking, security, and troubleshooting for AWS interviews.

---

## Table of Contents

1. [VPC Architecture](#vpc-architecture)
2. [Subnets and Routing](#subnets-and-routing)
3. [Security Groups vs NACLs](#security-groups-vs-nacls)
4. [Load Balancers](#load-balancers)
5. [VPC Peering and Transit Gateway](#vpc-peering-and-transit-gateway)
6. [DNS and Route 53](#dns-and-route-53)
7. [Troubleshooting](#troubleshooting)
8. [Interview Questions](#interview-questions)

---

## VPC Architecture

### Production VPC Design

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              VPC: 10.0.0.0/16                                   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                        AVAILABILITY ZONE A                               │  │
│  │                                                                          │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │  │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Private Subnet  │         │  │
│  │  │ 10.0.1.0/24     │  │ 10.0.10.0/24   │  │ 10.0.100.0/24  │         │  │
│  │  │                 │  │  (App Tier)     │  │  (Data Tier)    │         │  │
│  │  │  [NAT GW]       │  │  [EC2] [ECS]   │  │  [RDS] [Redis]  │         │  │
│  │  │  [Bastion]      │  │                 │  │                 │         │  │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘         │  │
│  │           │                    │                    │                   │  │
│  └───────────┼────────────────────┼────────────────────┼───────────────────┘  │
│              │                    │                    │                      │
│  ┌───────────┼────────────────────┼────────────────────┼───────────────────┐  │
│  │           │       AVAILABILITY ZONE B               │                   │  │
│  │           │                    │                    │                   │  │
│  │  ┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐         │  │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Private Subnet  │         │  │
│  │  │ 10.0.2.0/24     │  │ 10.0.20.0/24   │  │ 10.0.200.0/24  │         │  │
│  │  │                 │  │  (App Tier)     │  │  (Data Tier)    │         │  │
│  │  │  [NAT GW]       │  │  [EC2] [ECS]   │  │  [RDS Standby]  │         │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘         │  │
│  │                                                                          │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│                    ┌──────────────────────────────────────┐                    │
│                    │           Internet Gateway           │                    │
│                    └──────────────────────────────────────┘                    │
│                                      │                                         │
└──────────────────────────────────────┼─────────────────────────────────────────┘
                                       │
                                   Internet
```

### VPC Terraform Configuration

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.environment}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "${var.environment}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.environment}-public-${count.index + 1}"
    Type = "Public"
    "kubernetes.io/role/elb" = "1"  # For EKS
  }
}

# Private Subnets (App Tier)
resource "aws_subnet" "private_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "${var.environment}-private-app-${count.index + 1}"
    Type = "Private"
    Tier = "Application"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Private Subnets (Data Tier)
resource "aws_subnet" "private_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 100)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "${var.environment}-private-data-${count.index + 1}"
    Type = "Private"
    Tier = "Data"
  }
}

# NAT Gateways (one per AZ for HA)
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"
  
  tags = {
    Name = "${var.environment}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = {
    Name = "${var.environment}-nat-${count.index + 1}"
  }
  
  depends_on = [aws_internet_gateway.main]
}
```

---

## Subnets and Routing

### Route Table Configuration

```hcl
# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  # VPC Peering route (if applicable)
  route {
    cidr_block                = "172.16.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.shared.id
  }
  
  tags = {
    Name = "${var.environment}-public-rt"
  }
}

# Associate public subnets
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ for NAT redundancy)
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  
  tags = {
    Name = "${var.environment}-private-rt-${count.index + 1}"
  }
}
```

### CIDR Planning Guide

| Environment | VPC CIDR | Public | Private App | Private Data |
|-------------|----------|--------|-------------|--------------|
| Production | 10.0.0.0/16 | /24 (251 IPs) | /22 (1019 IPs) | /24 (251 IPs) |
| Staging | 10.1.0.0/16 | /24 | /23 | /24 |
| Development | 10.2.0.0/16 | /24 | /24 | /24 |

---

## Security Groups vs NACLs

### Comparison

| Feature | Security Groups | NACLs |
|---------|----------------|-------|
| **Level** | Instance/ENI | Subnet |
| **State** | Stateful | Stateless |
| **Rules** | Allow only | Allow & Deny |
| **Evaluation** | All rules | Rules in order |
| **Default** | Deny all inbound | Allow all |
| **Use Case** | Instance protection | Subnet-level blocking |

### Security Group Examples

```hcl
# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id
  
  # Allow HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }
  
  # Allow HTTP for redirect
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect"
  }
  
  # Allow outbound to app tier
  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "To application tier"
  }
  
  tags = {
    Name = "${var.environment}-alb-sg"
  }
}

# Application Security Group
resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Security group for application tier"
  vpc_id      = aws_vpc.main.id
  
  # Allow from ALB only
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "From ALB"
  }
  
  # Allow SSH from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion"
  }
  
  # Allow outbound to database
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
    description     = "To PostgreSQL"
  }
  
  # Allow outbound to Redis
  egress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.redis.id]
    description     = "To Redis"
  }
  
  # Allow outbound HTTPS (for AWS APIs)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound"
  }
  
  tags = {
    Name = "${var.environment}-app-sg"
  }
}

# Database Security Group
resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "From application tier"
  }
  
  # No egress needed for RDS
  
  tags = {
    Name = "${var.environment}-rds-sg"
  }
}
```

### NACL Examples

```hcl
# NACL for public subnets
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id
  
  # Inbound Rules
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  
  # Ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  
  # Block known bad IPs
  ingress {
    protocol   = -1
    rule_no    = 50
    action     = "deny"
    cidr_block = "123.45.67.0/24"  # Example blocked range
    from_port  = 0
    to_port    = 0
  }
  
  # Outbound Rules
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  
  tags = {
    Name = "${var.environment}-public-nacl"
  }
}
```

---

## Load Balancers

### Load Balancer Comparison

| Feature | ALB | NLB | CLB |
|---------|-----|-----|-----|
| **Layer** | 7 (HTTP/HTTPS) | 4 (TCP/UDP) | 4 & 7 |
| **Performance** | Good | Ultra-low latency | Legacy |
| **Protocols** | HTTP, HTTPS, gRPC | TCP, UDP, TLS | HTTP, HTTPS, TCP |
| **WebSockets** | Yes | Yes | Limited |
| **Static IP** | No (use Global Accelerator) | Yes | No |
| **Preserve Source IP** | Via X-Forwarded-For | Yes | No |
| **WAF** | Yes | No | No |
| **Use Case** | Web apps, APIs | Gaming, IoT, extreme performance | Legacy only |

### ALB with Path-Based Routing

```hcl
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  
  enable_deletion_protection = true
  enable_http2               = true
  ip_address_type            = "dualstack"  # IPv4 + IPv6
  
  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn
  
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# Path-based routing rules
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "web" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
  
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Host-based routing
resource "aws_lb_listener_rule" "admin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 50
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin.arn
  }
  
  condition {
    host_header {
      values = ["admin.example.com"]
    }
  }
}

# Weighted routing for canary
resource "aws_lb_listener_rule" "canary" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 90
  
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.stable.arn
        weight = 90
      }
      target_group {
        arn    = aws_lb_target_group.canary.arn
        weight = 10
      }
    }
  }
  
  condition {
    path_pattern {
      values = ["/api/v2/*"]
    }
  }
}
```

---

## VPC Peering and Transit Gateway

### VPC Peering

```
┌─────────────────────┐         ┌─────────────────────┐
│    VPC A            │         │    VPC B            │
│   10.0.0.0/16       │◄───────►│   172.16.0.0/16     │
│                     │ Peering │                     │
│   [App Servers]     │         │   [Shared Services] │
└─────────────────────┘         └─────────────────────┘
```

```hcl
# VPC Peering Connection
resource "aws_vpc_peering_connection" "main" {
  vpc_id        = aws_vpc.app.id
  peer_vpc_id   = aws_vpc.shared.id
  peer_region   = "us-east-1"  # For cross-region
  auto_accept   = false
  
  tags = {
    Name = "app-to-shared-peering"
  }
}

# Accept peering (in shared VPC account/region)
resource "aws_vpc_peering_connection_accepter" "shared" {
  provider                  = aws.shared
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
  auto_accept               = true
}

# Route in App VPC
resource "aws_route" "app_to_shared" {
  route_table_id            = aws_route_table.app_private.id
  destination_cidr_block    = "172.16.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}
```

### Transit Gateway

```
                    ┌─────────────────────────────┐
                    │      Transit Gateway        │
                    │    (Central Hub)            │
                    └───────────┬─────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│   VPC A       │      │   VPC B       │      │   VPC C       │
│  Production   │      │   Staging     │      │   Shared      │
│  10.0.0.0/16  │      │  10.1.0.0/16  │      │  172.16.0.0/16│
└───────────────┘      └───────────────┘      └───────────────┘
        │                       │
        │                       │
        ▼                       ▼
┌───────────────────────────────────────────────────────┐
│                   On-Premises                         │
│            (via VPN or Direct Connect)                │
└───────────────────────────────────────────────────────┘
```

```hcl
# Transit Gateway
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Main transit gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  
  tags = {
    Name = "main-tgw"
  }
}

# VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id
  
  dns_support        = "enable"
  
  tags = {
    Name = "production-attachment"
  }
}

# Route Table for segmentation
resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = {
    Name = "production-rt"
  }
}

# Association
resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Propagation (allows automatic route learning)
resource "aws_ec2_transit_gateway_route_table_propagation" "shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}
```

---

## DNS and Route 53

### DNS Record Types

| Type | Use Case | Example |
|------|----------|---------|
| **A** | IPv4 address | 192.0.2.1 |
| **AAAA** | IPv6 address | 2001:db8::1 |
| **CNAME** | Alias to another domain | app.example.com → lb.amazonaws.com |
| **ALIAS** | AWS-specific alias | example.com → ALB/CloudFront |
| **MX** | Mail servers | mail.example.com |
| **TXT** | Verification, SPF | v=spf1 include:_spf.google.com |
| **NS** | Name servers | ns-1234.awsdns-12.org |

### Route 53 Routing Policies

```hcl
# Simple routing
resource "aws_route53_record" "simple" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Weighted routing (for canary/blue-green)
resource "aws_route53_record" "weighted_primary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "primary"
  
  weighted_routing_policy {
    weight = 90
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "weighted_canary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "canary"
  
  weighted_routing_policy {
    weight = 10
  }
  
  alias {
    name                   = aws_lb.canary.dns_name
    zone_id                = aws_lb.canary.zone_id
    evaluate_target_health = true
  }
}

# Failover routing (for DR)
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

resource "aws_route53_record" "failover_primary" {
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

resource "aws_route53_record" "failover_secondary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "secondary"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.dr.dns_name
    zone_id                = aws_lb.dr.zone_id
    evaluate_target_health = true
  }
}

# Geolocation routing
resource "aws_route53_record" "geo_us" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "us"
  
  geolocation_routing_policy {
    country = "US"
  }
  
  alias {
    name                   = aws_lb.us.dns_name
    zone_id                = aws_lb.us.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "geo_eu" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "eu"
  
  geolocation_routing_policy {
    continent = "EU"
  }
  
  alias {
    name                   = aws_lb.eu.dns_name
    zone_id                = aws_lb.eu.zone_id
    evaluate_target_health = true
  }
}

# Latency-based routing
resource "aws_route53_record" "latency_us" {
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
```

---

## Troubleshooting

### Common Networking Issues

#### Issue 1: Instance Can't Reach Internet

```bash
# Diagnosis checklist
1. Check subnet route table → NAT/IGW route exists?
2. Check security group outbound rules
3. Check NACL rules (both inbound and outbound)
4. Check if NAT Gateway is healthy
5. Check instance has public/elastic IP (if in public subnet)

# Commands
aws ec2 describe-route-tables --route-table-id rtb-xxxxx
aws ec2 describe-security-groups --group-id sg-xxxxx
aws ec2 describe-network-acls --network-acl-id acl-xxxxx
aws ec2 describe-nat-gateways --nat-gateway-id nat-xxxxx
```

#### Issue 2: Cannot Connect to RDS

```bash
# Diagnosis checklist
1. Check security group allows traffic from app SG
2. Check RDS is in correct subnets
3. Check RDS is not publicly accessible (if private)
4. Verify VPC DNS resolution enabled
5. Check RDS endpoint is correct

# Test connectivity from EC2
nc -zv rds-endpoint.region.rds.amazonaws.com 5432
telnet rds-endpoint.region.rds.amazonaws.com 5432
```

#### Issue 3: ALB Returns 504 Gateway Timeout

```bash
# Possible causes
1. Target is not responding within timeout
2. Target security group blocking ALB
3. Target health check failing
4. Application crashed or overloaded

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...
  
# Check ALB access logs
# s3://bucket/AWSLogs/account-id/elasticloadbalancing/region/
```

### VPC Flow Logs Analysis

```hcl
# Enable VPC Flow Logs
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  
  tags = {
    Name = "vpc-flow-logs"
  }
}
```

```bash
# Flow log format
# version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status

# ACCEPT = traffic was allowed
# REJECT = traffic was blocked

# Example rejected traffic (blocked by SG/NACL)
# 2 123456789012 eni-abc123 10.0.1.5 10.0.2.10 49152 3389 6 1 40 1620140761 1620140821 REJECT OK
```

---

## Interview Questions

### Q1: Explain the difference between Security Groups and NACLs. When would you use each?

**Answer:**

| Aspect | Security Groups | NACLs |
|--------|-----------------|-------|
| **State** | Stateful (return traffic automatic) | Stateless (must allow both directions) |
| **Scope** | Instance level | Subnet level |
| **Rules** | Allow only | Allow and Deny |
| **Order** | All rules evaluated | Rules evaluated in order |

**Use Security Groups for:**
- Normal instance-level protection
- Referencing other security groups
- Primary defense mechanism

**Use NACLs for:**
- Blocking specific IP ranges
- Additional layer of defense
- Quick temporary blocks
- Compliance requirements

---

### Q2: You have instances in a private subnet that can't reach the internet. How do you troubleshoot?

**Answer:**

1. **Check NAT Gateway:**
   ```bash
   aws ec2 describe-nat-gateways --filter "Name=state,Values=available"
   ```
   - Is NAT Gateway in available state?
   - Is it in a public subnet?
   - Does it have an Elastic IP?

2. **Check Route Table:**
   ```bash
   aws ec2 describe-route-tables --route-table-id rtb-xxxxx
   ```
   - Is there a route to 0.0.0.0/0 via NAT Gateway?
   - Is the route table associated with the subnet?

3. **Check Security Groups:**
   - Is outbound traffic allowed to the destination?

4. **Check NACLs:**
   - Do NACLs allow outbound traffic?
   - Do NACLs allow inbound ephemeral ports (1024-65535)?

5. **Check NAT Gateway SG/NACL:**
   - NAT Gateway's subnet NACL must allow traffic

---

### Q3: Design the VPC architecture for a multi-tier application with these requirements: High availability, separation of concerns, compliance (PCI-DSS).

**Answer:**

```
VPC: 10.0.0.0/16 (3 AZs)

Public Subnets (DMZ):
- 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
- NAT Gateways, Bastion hosts, ALB

Private Subnets (App Tier):
- 10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24
- Application servers, internal ALB

Private Subnets (Data Tier - Isolated):
- 10.0.100.0/24, 10.0.200.0/24, 10.0.300.0/24
- RDS, ElastiCache, no internet access

PCI Compliance considerations:
1. Separate subnets for cardholder data
2. Strict security groups (least privilege)
3. VPC Flow Logs enabled
4. NACLs as additional layer
5. No direct internet access to data tier
6. Encrypted data in transit (TLS) and at rest
7. WAF on ALB
8. Regular vulnerability scanning
```
