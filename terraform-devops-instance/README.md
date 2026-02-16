# DevOps Instance with Pre-installed Tools

Terraform configuration to create EC2 instances with all essential DevOps and MLOps tools pre-installed, integrated with AWS Systems Manager (SSM) for secure access and CloudWatch for session logging.

## Architecture

- **VPC**: Custom VPC with public subnet
- **EC2 Instance**: Amazon Linux 2023, t3.large (30GB encrypted EBS)
- **Security**: SSH access, IAM role with SSM and CloudWatch access
- **SSM Agent**: Pre-installed and configured for secure connections
- **CloudWatch**: Session logs sent to `/aws/ssm/devops-instance`
- **SSM Parameter Store**: Centralized package repository information
- **Scalability**: Configurable instance count via `instance_count` variable
- **Tools**: Docker, Kubernetes, Terraform, Python, Java, Node.js, AWS CLI, and more

## Pre-installed Tools (Latest Stable Versions)

### Container & Orchestration
- Docker (latest from Amazon Linux repo)
- Docker Compose (latest)
- Kubernetes (kubectl - latest stable)
- Helm 3 (latest)
- k9s (latest)
- eksctl (latest)

### Infrastructure as Code
- Terraform 1.10.3
- Ansible (latest)

### Programming Languages
- Python 3.12 + pip
- Java 21 (Amazon Corretto)
- Maven 3.9.9
- Node.js 22 LTS + npm

### Cloud & DevOps
- AWS CLI v2 (latest)
- Jenkins CLI (latest)
- Trivy 0.58.1 (security scanner)

### Networking Tools
- curl, wget, telnet, nc
- net-tools, bind-utils
- traceroute, tcpdump

### Development Tools
- Git, vim, jq
- unzip, tar, gzip

## Version Management

All tool versions are configurable via variables in `variables.tf`. Default versions are set to latest stable releases. To customize versions, edit `terraform.tfvars`:

```hcl
terraform_version = "1.10.3"
python_version    = "3.12"
java_version      = "21"
maven_version     = "3.9.9"
nodejs_version    = "22"
trivy_version     = "0.58.1"
```

## Prerequisites

1. AWS CLI configured
2. Terraform >= 1.0
3. ~~EC2 key pair created in your AWS region~~ (Key pair will be auto-generated)

## File Structure

```
.
├── versions.tf              # Provider configuration (AWS, TLS, Local)
├── variables.tf             # Input variables with tool versions
├── terraform.tfvars.example # Example variable values
├── keypair.tf               # SSH key pair generation (RSA 4096)
├── vpc.tf                   # VPC, subnet, IGW, route tables
├── security_group.tf        # Security group with SSH access
├── iam.tf                   # IAM role with SSM, CloudWatch, Parameter Store access
├── cloudwatch.tf            # CloudWatch log group and SSM session document
├── ssm_parameters.tf        # SSM parameters for DevOps/MLOps packages
├── ec2.tf                   # EC2 instances with user_data
├── user_data.sh            # Tool installation and SSM configuration script
├── outputs.tf              # Output values (IPs, SSH commands, SSM commands)
├── .gitignore              # Git ignore rules
└── README.md               # This file
```

## Deployment

1. **Create terraform.tfvars**:
```bash
cp terraform.tfvars.example terraform.tfvars
```

2. **Edit terraform.tfvars**:
```hcl
aws_region       = "us-west-2"
key_name         = "devops-key"  # Name for the new key pair
ssh_allowed_cidr = "YOUR_IP/32"  # Restrict SSH to your IP
instance_count   = 2  # Number of instances to create
```

3. **Initialize Terraform**:
```bash
terraform init
```

4. **Review the plan**:
```bash
terraform plan
```

5. **Apply the configuration**:
```bash
terraform apply
```

Terraform will create a new SSH key pair and save the private key as `<key_name>.pem` in the project directory.

6. **Connect to instance**:

**Via SSH:**
```bash
ssh -i <key_name>.pem ec2-user@<PUBLIC_IP>
# Or use the output command for first instance:
terraform output -json ssh_command | jq -r '.[0]'
```

**Via AWS SSM (Recommended - No SSH key needed):**
```bash
# Connect to first instance
terraform output -json ssm_connect_command | jq -r '.[0]' | bash

# Or directly
aws ssm start-session --target <INSTANCE_ID> --region us-west-2
```

## Post-Deployment

After connecting to the instance:

1. **Check installed tools**:
```bash
cat ~/tool-versions.txt
```

2. **Verify Docker**:
```bash
docker --version
docker ps
```

3. **Verify Kubernetes tools**:
```bash
kubectl version --client
helm version
```

4. **Verify programming languages**:
```bash
python3 --version
java -version
node --version
```

5. **Verify AWS CLI**:
```bash
aws --version
aws configure  # Configure if needed
```

6. **View DevOps packages from SSM**:
```bash
cat ~/devops-packages.json | jq .
```

7. **View MLOps packages from SSM**:
```bash
cat ~/mlops-packages.json | jq .
```

8. **Install MLOps packages** (optional):
```bash
aws ssm get-parameter --name "/devops-instance/scripts/install-mlops" --query 'Parameter.Value' --output text > install-mlops.sh
chmod +x install-mlops.sh
./install-mlops.sh
```

9. **View SSM session logs**:
```bash
aws logs tail /aws/ssm/devops-instance --follow
```

## Security Recommendations

1. **Restrict SSH access**: Change `ssh_allowed_cidr` to your specific IP
2. **Use Session Manager**: Connect via AWS Systems Manager instead of SSH (no open ports needed)
3. **SSM Connection**: `aws ssm start-session --target <instance-id>` (requires AWS CLI and Session Manager plugin)
4. **Enable CloudWatch**: Add CloudWatch agent for monitoring
5. **Regular updates**: Run `dnf update -y` regularly

## Customization

### Change instance type
Edit `terraform.tfvars`:
```hcl
instance_type = "t3.xlarge"  # For more resources
```

### Create multiple instances
Edit `terraform.tfvars`:
```hcl
instance_count = 3  # Create 3 instances
```

### Add more tools
Edit `user_data.sh` and add installation commands.

### Change region
Edit `terraform.tfvars`:
```hcl
aws_region        = "us-east-1"
availability_zone = "us-east-1a"
```

## Advanced Usage

### View All SSM Parameters
```bash
# List all parameters
aws ssm describe-parameters --filters "Key=Name,Values=/devops-instance/"

# Get DevOps packages
aws ssm get-parameter --name "/devops-instance/packages/devops" --query 'Parameter.Value' --output text | jq .

# Get MLOps packages
aws ssm get-parameter --name "/devops-instance/packages/mlops" --query 'Parameter.Value' --output text | jq .
```

### Monitor SSM Sessions in Real-time
```bash
# Tail CloudWatch logs
aws logs tail /aws/ssm/devops-instance --follow

# Filter by instance
aws logs tail /aws/ssm/devops-instance --follow --filter-pattern "i-1234567890abcdef0"
```

### Update Package Repositories
```bash
# Update DevOps packages parameter
aws ssm put-parameter --name "/devops-instance/packages/devops" --value '{"docker":{"version":"latest"}}' --overwrite

# Update MLOps packages parameter
aws ssm put-parameter --name "/devops-instance/packages/mlops" --value '{"mlflow":{"version":"2.10.0"}}' --overwrite
```

### Connect to Multiple Instances
```bash
# Get all instance IDs
terraform output -json instance_id | jq -r '.[]'

# Connect to specific instance
aws ssm start-session --target <INSTANCE_ID>

# Run command on all instances
for id in $(terraform output -json instance_id | jq -r '.[]'); do
  aws ssm send-command --instance-ids "$id" --document-name "AWS-RunShellScript" --parameters 'commands=["uptime"]'
done
```

## Cleanup

```bash
terraform destroy
```

## Outputs

- `instance_id`: EC2 instance IDs (array)
- `instance_public_ip`: Public IP addresses (array)
- `instance_public_dns`: Public DNS names (array)
- `instance_names`: Instance names (array)
- `ssh_command`: Ready-to-use SSH commands (array)
- `ssm_connect_command`: AWS SSM Session Manager commands (array)
- `private_key_path`: Path to generated private key file
- `key_pair_name`: AWS key pair name
- `cloudwatch_log_group`: CloudWatch log group name for SSM sessions
- `ssm_document_name`: SSM document name for session preferences
- `ssm_parameters`: SSM parameter names for package repositories
  - `devops_packages`: DevOps tools and repositories
  - `mlops_packages`: MLOps frameworks and tools
  - `languages`: Programming language versions
  - `mlops_install_script`: MLOps installation script
- `vpc_id`: VPC ID
- `subnet_id`: Subnet ID

## Troubleshooting

### Tools not installed
Check user data execution:
```bash
# Check if user data is running/completed
sudo cat /var/log/user-data.log
sudo cat /var/log/user-data-complete.log

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check status
cat /tmp/user-data-status
```

### Docker permission denied
Logout and login again, or run:
```bash
newgrp docker
```

### AWS CLI not configured
```bash
aws configure
# Enter your AWS credentials
```

### SSM Session Manager not working
Install Session Manager plugin:
```bash
# macOS
brew install --cask session-manager-plugin

# Linux
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
sudo yum install -y session-manager-plugin.rpm
```

### CloudWatch logs not appearing
Check IAM permissions and SSM document:
```bash
# Verify SSM document
aws ssm describe-document --name "devops-instance-session-manager-prefs"

# Check CloudWatch log group
aws logs describe-log-groups --log-group-name-prefix "/aws/ssm/devops-instance"
```

### SSM Parameter Store access denied
Verify IAM role has correct permissions:
```bash
# Test parameter access
aws ssm get-parameter --name "/devops-instance/packages/devops"
```

## Cost Estimate

- **t3.large**: ~$0.0832/hour (~$60/month)
- **30GB EBS gp3**: ~$2.40/month
- **Data transfer**: Variable

**Total**: ~$62-65/month (us-west-2)

## Notes

- Instance uses Amazon Linux 2023 (latest stable)
- All tools are installed at launch via user_data script
- Docker group membership requires re-login to take effect
- Root volume is encrypted by default (gp3, 30GB)
- **SSM Agent**: Pre-installed, enabled, and configured automatically
- **Session Logging**: All SSM sessions logged to CloudWatch (`/aws/ssm/devops-instance`)
- **Log Retention**: 7 days (configurable in `cloudwatch.tf`)
- **Package Repository**: DevOps and MLOps package info stored in SSM Parameter Store
- **SSM Access**: Enabled via IAM role (no SSH keys or open ports needed)
- **SSH Key Pair**: Auto-generated RSA 4096-bit key saved as `<key_name>.pem`
- **Security**: Keep the .pem file secure - it's your only way to SSH
- **Git**: Private key file automatically added to .gitignore
- **Scalability**: Create multiple instances by setting `instance_count` variable
- **Consistency**: All instances share the same configuration and tools
- **Cost**: ~$60-65/month per t3.large instance in us-west-2
- **Updates**: System packages updated at launch (curl excluded to avoid conflicts)
