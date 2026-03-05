# AWS Security Deep Dive

Complete guide to AWS security best practices, IAM, encryption, and compliance.

---

## Table of Contents

1. [IAM (Identity and Access Management)](#iam-identity-and-access-management)
2. [Network Security](#network-security)
3. [Data Encryption](#data-encryption)
4. [Secrets Management](#secrets-management)
5. [Security Services](#security-services)
6. [Compliance and Auditing](#compliance-and-auditing)
7. [Security Incident Response](#security-incident-response)
8. [Interview Questions](#interview-questions)

---

## IAM (Identity and Access Management)

### IAM Components

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                  AWS ACCOUNT                                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                              IAM                                         │   │
│  │                                                                          │   │
│  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐ │   │
│  │  │   USERS     │   │   GROUPS    │   │   ROLES     │   │  POLICIES   │ │   │
│  │  │             │   │             │   │             │   │             │ │   │
│  │  │ • Admin     │   │ • Admins    │   │ • EC2Role   │   │ • Managed   │ │   │
│  │  │ • Developer │──▶│ • Devs      │   │ • Lambda    │   │ • Inline    │ │   │
│  │  │ • Ops       │   │ • ReadOnly  │   │ • ECS Task  │   │ • Customer  │ │   │
│  │  │             │   │             │   │ • CrossAcct │   │             │ │   │
│  │  └─────────────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘ │   │
│  │                           │                  │                 │        │   │
│  │                           └──────────────────┴─────────────────┘        │   │
│  │                                              │                          │   │
│  │                                    ATTACHED TO                          │   │
│  │                                                                          │   │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │   │
│  │  │                         RESOURCES                                  │  │   │
│  │  │                                                                    │  │   │
│  │  │  EC2  │  S3  │  RDS  │  Lambda  │  DynamoDB  │  Secrets Manager  │  │   │
│  │  │                                                                    │  │   │
│  │  └───────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### IAM Best Practices

| Practice | Description |
|----------|-------------|
| **Least Privilege** | Grant minimum permissions needed |
| **Use Roles** | Prefer roles over long-term credentials |
| **MFA** | Enable MFA for all human users |
| **Rotate Credentials** | Regular key rotation |
| **No Root** | Never use root account for daily tasks |
| **Conditions** | Use conditions for fine-grained access |
| **Service Control Policies** | Organizational guardrails |

### Policy Examples

```hcl
# Least privilege EC2 role
resource "aws_iam_role" "app_server" {
  name = "app-server-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_server" {
  name = "app-server-policy"
  role = aws_iam_role.app_server.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSpecificS3Bucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::my-app-bucket",
          "arn:aws:s3:::my-app-bucket/*"
        ]
      },
      {
        Sid    = "WriteToSpecificDynamoDBTable"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          "arn:aws:dynamodb:us-east-1:123456789012:table/my-app-table",
          "arn:aws:dynamodb:us-east-1:123456789012:table/my-app-table/index/*"
        ]
      },
      {
        Sid    = "AccessSpecificSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-app/*"
        ]
        Condition = {
          StringEquals = {
            "secretsmanager:ResourceTag/Environment" = "production"
          }
        }
      },
      {
        Sid    = "DecryptWithKMS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
        ]
      }
    ]
  })
}
```

### Cross-Account Access

```hcl
# Role in Account B (target account)
resource "aws_iam_role" "cross_account" {
  name = "cross-account-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::111111111111:root"  # Account A
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "unique-external-id"  # Confused deputy protection
        }
      }
    }]
  })
}

# Policy in Account A to assume role
resource "aws_iam_policy" "assume_cross_account" {
  name = "assume-cross-account"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::222222222222:role/cross-account-role"
    }]
  })
}
```

### Service Control Policies (SCPs)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnapprovedRegions",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2", "eu-west-1"]
        }
      }
    },
    {
      "Sid": "DenyLeaveOrganization",
      "Effect": "Deny",
      "Action": "organizations:LeaveOrganization",
      "Resource": "*"
    },
    {
      "Sid": "RequireIMDSv2",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    },
    {
      "Sid": "RequireEncryptedEBS",
      "Effect": "Deny",
      "Action": "ec2:CreateVolume",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "ec2:Encrypted": "false"
        }
      }
    }
  ]
}
```

---

## Network Security

### Security Architecture

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              NETWORK SECURITY                                   │
│                                                                                 │
│  INTERNET                                                                       │
│      │                                                                          │
│      ▼                                                                          │
│  ┌────────────────┐                                                            │
│  │   AWS Shield   │ ← DDoS Protection                                          │
│  │   (Standard)   │                                                            │
│  └───────┬────────┘                                                            │
│          │                                                                      │
│          ▼                                                                      │
│  ┌────────────────┐                                                            │
│  │   AWS WAF      │ ← Web Application Firewall                                 │
│  │                │   • SQL Injection protection                               │
│  │                │   • XSS protection                                         │
│  │                │   • Rate limiting                                          │
│  │                │   • IP blocking                                            │
│  └───────┬────────┘                                                            │
│          │                                                                      │
│          ▼                                                                      │
│  ┌────────────────┐                                                            │
│  │  CloudFront    │ ← Edge caching + SSL termination                          │
│  └───────┬────────┘                                                            │
│          │                                                                      │
│          ▼                                                                      │
│  ┌────────────────────────────────────────────────────────────────────┐       │
│  │                            VPC                                      │       │
│  │                                                                     │       │
│  │  ┌──────────────────────────────────────────────────────────────┐ │       │
│  │  │                    PUBLIC SUBNETS                             │ │       │
│  │  │    ┌─────────┐                          ┌──────────────┐     │ │       │
│  │  │    │   ALB   │◄── NACL ←────────────────│ Network ACL  │     │ │       │
│  │  │    └────┬────┘                          └──────────────┘     │ │       │
│  │  │         │                                                     │ │       │
│  │  │         │  ┌──────────────────┐                              │ │       │
│  │  │         │  │  Security Group  │ ← Stateful firewall          │ │       │
│  │  │         │  │  (ALB SG)        │                              │ │       │
│  │  │         │  │  Inbound: 443    │                              │ │       │
│  │  │         │  └──────────────────┘                              │ │       │
│  │  └─────────┼─────────────────────────────────────────────────────┘ │       │
│  │            │                                                        │       │
│  │  ┌─────────┼─────────────────────────────────────────────────────┐ │       │
│  │  │         ▼        PRIVATE SUBNETS                              │ │       │
│  │  │    ┌──────────┐                                               │ │       │
│  │  │    │   EC2    │◄──┌──────────────────┐                       │ │       │
│  │  │    │ Instances│   │  Security Group  │                       │ │       │
│  │  │    └─────┬────┘   │  (App SG)        │                       │ │       │
│  │  │          │        │  Inbound: 8080   │                       │ │       │
│  │  │          │        │  from ALB SG     │                       │ │       │
│  │  │          │        └──────────────────┘                       │ │       │
│  │  │          │                                                    │ │       │
│  │  │          ▼                                                    │ │       │
│  │  │    ┌──────────┐                                               │ │       │
│  │  │    │   RDS    │◄──┌──────────────────┐                       │ │       │
│  │  │    │          │   │  Security Group  │                       │ │       │
│  │  │    └──────────┘   │  (RDS SG)        │                       │ │       │
│  │  │                   │  Inbound: 5432   │                       │ │       │
│  │  │                   │  from App SG     │                       │ │       │
│  │  │                   └──────────────────┘                       │ │       │
│  │  └───────────────────────────────────────────────────────────────┘ │       │
│  │                                                                     │       │
│  └─────────────────────────────────────────────────────────────────────┘       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### AWS WAF Rules

```hcl
resource "aws_wafv2_web_acl" "main" {
  name        = "production-waf"
  scope       = "REGIONAL"  # or CLOUDFRONT
  description = "Production WAF rules"
  
  default_action {
    allow {}
  }
  
  # AWS Managed Rules - Core
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
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  # SQL Injection Protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2
    
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
      metric_name                = "SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  # Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 3
    
    action {
      block {}
    }
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }
  
  # IP Blocklist
  rule {
    name     = "IPBlocklist"
    priority = 0
    
    action {
      block {}
    }
    
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocklist.arn
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPBlocklistMetric"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ProductionWAFMetric"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_ip_set" "blocklist" {
  name               = "ip-blocklist"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.blocked_ips
}
```

---

## Data Encryption

### Encryption at Rest

```hcl
# KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "Main encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow service-linked role use"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.app_server.arn,
            aws_iam_role.lambda.arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow attachment of persistent resources"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.app_server.arn
        }
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/main"
  target_key_id = aws_kms_key.main.key_id
}

# S3 encryption
resource "aws_s3_bucket" "encrypted" {
  bucket = "my-encrypted-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted" {
  bucket = aws_s3_bucket.encrypted.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true  # Cost optimization
  }
}

# RDS encryption
resource "aws_db_instance" "encrypted" {
  identifier     = "encrypted-db"
  engine         = "postgres"
  instance_class = "db.r6g.large"
  
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn
  
  # ... other configuration
}

# EBS encryption (default)
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "main" {
  key_arn = aws_kms_key.main.arn
}
```

### Encryption in Transit

```hcl
# ALB with TLS 1.3
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# RDS with SSL
resource "aws_db_parameter_group" "ssl_required" {
  family = "postgres15"
  name   = "ssl-required"
  
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

# ElastiCache with TLS
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "secure-redis"
  
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = var.redis_auth_token
}
```

---

## Secrets Management

### Secrets Manager

```hcl
# Create secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "prod/database/credentials"
  description = "Database credentials for production"
  kms_key_id  = aws_kms_key.main.arn
  
  tags = {
    Environment = "production"
    Application = "api"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.main.endpoint
    port     = 5432
    database = "appdb"
  })
}

# Automatic rotation
resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn
  
  rotation_rules {
    automatically_after_days = 30
  }
}
```

### SSM Parameter Store

```hcl
# Secure parameter (encrypted)
resource "aws_ssm_parameter" "api_key" {
  name        = "/prod/api/key"
  description = "API key for external service"
  type        = "SecureString"
  value       = var.api_key
  key_id      = aws_kms_key.main.arn
  
  tags = {
    Environment = "production"
  }
}

# Retrieve in Lambda
resource "aws_lambda_function" "api" {
  # ...
  
  environment {
    variables = {
      API_KEY_PARAM = aws_ssm_parameter.api_key.name
    }
  }
}
```

---

## Security Services

### GuardDuty

```hcl
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# Auto-remediation via EventBridge
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-high-severity"
  description = "Capture high severity GuardDuty findings"
  
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "ProcessGuardDutyFinding"
  arn       = aws_lambda_function.security_response.arn
}
```

### Security Hub

```hcl
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
  
  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  
  depends_on = [aws_securityhub_account.main]
}
```

---

## Compliance and Auditing

### CloudTrail Configuration

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "main-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  
  kms_key_id = aws_kms_key.cloudtrail.arn
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::sensitive-bucket/"]
    }
    
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }
  
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
  
  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }
}
```

### AWS Config Rules

```hcl
resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  
  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "encrypted-volumes"
  
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
}

resource "aws_config_config_rule" "iam_password_policy" {
  name = "iam-password-policy"
  
  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }
  
  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols             = "true"
    RequireNumbers             = "true"
    MinimumPasswordLength      = "14"
    PasswordReusePrevention    = "24"
    MaxPasswordAge             = "90"
  })
}
```

---

## Security Incident Response

### Incident Response Playbook

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                         SECURITY INCIDENT RESPONSE                              │
│                                                                                 │
│  1. DETECTION                    2. CONTAINMENT                                │
│  ┌─────────────┐                ┌─────────────────┐                           │
│  │ GuardDuty   │───────────────▶│ Isolate affected│                           │
│  │ CloudWatch  │                │ resources       │                           │
│  │ WAF Alerts  │                │                 │                           │
│  │ SecurityHub │                │ • Block IPs     │                           │
│  └─────────────┘                │ • Revoke keys   │                           │
│                                 │ • Isolate EC2   │                           │
│                                 └────────┬────────┘                           │
│                                          │                                     │
│  3. ERADICATION                 4. RECOVERY                                   │
│  ┌─────────────────┐           ┌─────────────────┐                           │
│  │ Remove malware   │◀─────────│ Restore from    │                           │
│  │ Patch systems    │          │ clean backups   │                           │
│  │ Reset credentials│──────────▶│ Verify integrity│                           │
│  └─────────────────┘           │ Resume services │                           │
│                                └────────┬────────┘                           │
│                                         │                                     │
│  5. LESSONS LEARNED            6. DOCUMENTATION                              │
│  ┌─────────────────┐           ┌─────────────────┐                           │
│  │ Post-mortem     │◀──────────│ Timeline        │                           │
│  │ Update playbooks│           │ Evidence        │                           │
│  │ Improve controls│           │ Actions taken   │                           │
│  └─────────────────┘           └─────────────────┘                           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Automated Response Example

```python
# Lambda function for automated security response
import boto3
import json

ec2 = boto3.client('ec2')
iam = boto3.client('iam')
sns = boto3.client('sns')

def handler(event, context):
    finding = event['detail']
    finding_type = finding['type']
    severity = finding['severity']
    
    if 'UnauthorizedAccess:EC2' in finding_type:
        # Isolate compromised EC2 instance
        instance_id = finding['resource']['instanceDetails']['instanceId']
        isolate_instance(instance_id)
        notify_security_team(finding)
        
    elif 'UnauthorizedAccess:IAMUser' in finding_type:
        # Disable compromised IAM user
        username = finding['resource']['accessKeyDetails']['userName']
        disable_user(username)
        notify_security_team(finding)
    
    return {'statusCode': 200}

def isolate_instance(instance_id):
    """Replace security group with isolation SG"""
    # Get instance VPC
    instance = ec2.describe_instances(InstanceIds=[instance_id])
    vpc_id = instance['Reservations'][0]['Instances'][0]['VpcId']
    
    # Create or get isolation security group
    isolation_sg = get_or_create_isolation_sg(vpc_id)
    
    # Apply isolation security group
    ec2.modify_instance_attribute(
        InstanceId=instance_id,
        Groups=[isolation_sg]
    )
    
    print(f"Isolated instance {instance_id}")

def disable_user(username):
    """Disable IAM user and deactivate access keys"""
    # List and deactivate all access keys
    keys = iam.list_access_keys(UserName=username)
    for key in keys['AccessKeyMetadata']:
        iam.update_access_key(
            UserName=username,
            AccessKeyId=key['AccessKeyId'],
            Status='Inactive'
        )
    
    # Remove from all groups
    groups = iam.list_groups_for_user(UserName=username)
    for group in groups['Groups']:
        iam.remove_user_from_group(
            GroupName=group['GroupName'],
            UserName=username
        )
    
    print(f"Disabled user {username}")

def notify_security_team(finding):
    """Send alert to security team"""
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:123456789012:security-alerts',
        Subject=f"Security Alert: {finding['type']}",
        Message=json.dumps(finding, indent=2)
    )
```

---

## Interview Questions

### Q1: How would you implement least privilege access for a Lambda function that needs to read from S3 and write to DynamoDB?

**Answer:**

```hcl
resource "aws_iam_role_policy" "lambda_minimal" {
  name = "lambda-minimal-policy"
  role = aws_iam_role.lambda.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSpecificS3Objects"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "arn:aws:s3:::my-bucket/specific-prefix/*"
      },
      {
        Sid    = "WriteSpecificDynamoDBTable"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:123456789012:table/my-table"
        Condition = {
          "ForAllValues:StringEquals": {
            "dynamodb:LeadingKeys": ["${aws:userid}"]
          }
        }
      }
    ]
  })
}
```

**Key principles:**
- Specific resources, not wildcards
- Only required actions
- Conditions for additional restrictions
- Use attribute-based access control when possible

---

### Q2: An IAM access key was exposed on GitHub. What immediate actions would you take?

**Answer:**

**Immediate (within minutes):**
1. **Deactivate the key:**
   ```bash
   aws iam update-access-key --user-name <user> --access-key-id <key-id> --status Inactive
   ```

2. **Review CloudTrail for unauthorized activity:**
   ```bash
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<key-id>
   ```

3. **Rotate all credentials for the user**

**Short-term (within hours):**
4. Analyze what resources were accessed
5. Check for persistence mechanisms (new users, roles, keys)
6. Review and revoke any suspicious sessions
7. Enable MFA if not already enabled

**Long-term:**
8. Implement git-secrets or similar tool
9. Review IAM policies for blast radius
10. Consider AWS Secrets Manager for secrets
11. Post-mortem and process improvement

---

### Q3: Design a secure architecture for handling PCI-DSS compliant payment data.

**Answer:**

```
                    ┌─────────────────────────────────────────┐
                    │           PCI Compliant Zone            │
                    │                                         │
                    │  ┌─────────────────────────────────┐   │
                    │  │    Isolated VPC (10.100.0.0/16) │   │
                    │  │                                  │   │
Client ──HTTPS───▶ WAF ──▶ ALB ──▶  Private Subnet      │   │
                    │  │            │                     │   │
                    │  │            ▼                     │   │
                    │  │     ┌──────────────┐            │   │
                    │  │     │ Payment App  │            │   │
                    │  │     │ (Fargate)    │            │   │
                    │  │     │ Hardened     │            │   │
                    │  │     └───────┬──────┘            │   │
                    │  │             │                    │   │
                    │  │     ┌───────▼──────┐            │   │
                    │  │     │ RDS (encrypted│            │   │
                    │  │     │ Multi-AZ)    │            │   │
                    │  │     └──────────────┘            │   │
                    │  │                                  │   │
                    │  └─────────────────────────────────┘   │
                    │                                         │
                    │  Security Controls:                     │
                    │  • VPC Flow Logs enabled               │
                    │  • CloudTrail for all events           │
                    │  • GuardDuty enabled                   │
                    │  • Config rules for compliance         │
                    │  • KMS encryption everywhere           │
                    │  • No internet egress (VPC endpoints)  │
                    │  • Strict NACLs                        │
                    └─────────────────────────────────────────┘
```
