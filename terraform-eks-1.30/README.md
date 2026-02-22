# EKS 1.30 Cluster with Terraform

Production-ready EKS 1.30 cluster with 2 node groups (1 node each) following AWS best practices.

## Architecture

- **EKS Version**: 1.30
- **Node Groups**: 2 (General On-Demand + Spot)
- **Nodes**: 1 node per group (scalable to 3-5)
- **Networking**: VPC with public/private subnets across 2 AZs
- **Security**: KMS encryption, CloudWatch logging, proper security groups
- **Addons**: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver

## Best Practices Implemented

### Security
- KMS encryption for secrets with key rotation
- Private subnets for worker nodes
- Security groups with least privilege
- OIDC provider for IRSA
- SSM access for nodes (no SSH keys)
- CloudWatch logging for control plane

### High Availability
- Multi-AZ deployment (2 availability zones)
- NAT gateway per AZ for redundancy
- Mixed capacity (On-Demand + Spot instances)

### Networking
- Proper VPC tagging for EKS
- Public and private subnets
- Internet Gateway and NAT Gateways
- Endpoint access: private + public

### Observability
- Control plane logging (API, audit, authenticator, controller, scheduler)
- CloudWatch log group with 7-day retention

### Cost Optimization
- Spot instances for non-critical workloads
- Right-sized instances (t3.medium)
- Auto-scaling enabled

## Prerequisites

- AWS CLI configured
- Terraform >= 1.10.0
- kubectl

## Deployment

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Review the Plan
```bash
terraform plan
```

### 3. Deploy the Cluster
```bash
terraform apply
```

Deployment takes approximately 15-20 minutes.

### 4. Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-cluster
```

### 5. Verify the Cluster
```bash
kubectl get nodes
kubectl get pods -A
```

## Configuration

Edit variables.tf or create terraform.tfvars:

```hcl
aws_region      = "us-east-1"
project_name    = "my-eks-cluster"
environment     = "production"
cluster_version = "1.30"
vpc_cidr        = "10.0.0.0/16"
azs             = ["us-east-1a", "us-east-1b"]
```

## Node Groups

### General Node Group
- Type: On-Demand
- Instance: t3.medium
- Nodes: 1 (min: 1, max: 3)
- Use Case: Critical workloads

### Spot Node Group
- Type: Spot
- Instances: t3.medium, t3a.medium
- Nodes: 1 (min: 1, max: 5)
- Use Case: Fault-tolerant workloads

## Cleanup

```bash
terraform destroy
```

## Cost Estimate

Approximate monthly cost (us-east-1):
- EKS Control Plane: $73
- 2x t3.medium nodes: ~$60
- NAT Gateways (2): ~$65
- Total: ~$198/month
