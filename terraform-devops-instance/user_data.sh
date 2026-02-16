#!/bin/bash
set -ex
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user data script at $(date)"

# Tool versions
TERRAFORM_VERSION="${terraform_version}"
MAVEN_VERSION="${maven_version}"
NODEJS_VERSION="${nodejs_version}"
PYTHON_VERSION="${python_version}"
JAVA_VERSION="${java_version}"
TRIVY_VERSION="${trivy_version}"
PROJECT_NAME="${project_name}"
AWS_REGION="${aws_region}"

echo "Tool versions: Terraform=$TERRAFORM_VERSION, Maven=$MAVEN_VERSION, Node=$NODEJS_VERSION, Python=$PYTHON_VERSION, Java=$JAVA_VERSION, Trivy=$TRIVY_VERSION"

# Update system (skip curl conflicts)
echo "Updating system..."
dnf update -y --skip-broken --exclude=curl*

# Install basic tools
echo "Installing basic tools..."
dnf install -y git curl wget vim unzip tar gzip jq net-tools bind-utils telnet nc traceroute tcpdump

# Install Docker (latest from Amazon Linux repo)
echo "Installing Docker..."
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose (latest)
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install kubectl (latest stable)
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# Install Helm (latest)
echo "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Terraform
echo "Installing Terraform $TERRAFORM_VERSION..."
wget -q https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
unzip -q terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
rm -f terraform_$${TERRAFORM_VERSION}_linux_amd64.zip

# Install AWS CLI v2 (latest)
echo "Installing AWS CLI v2..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Python
echo "Installing Python $PYTHON_VERSION..."
dnf install -y python$${PYTHON_VERSION} python$${PYTHON_VERSION}-pip
alternatives --set python3 /usr/bin/python$${PYTHON_VERSION}
pip3 install --upgrade pip --quiet

# Install Java (Amazon Corretto)
echo "Installing Java $JAVA_VERSION..."
dnf install -y java-$${JAVA_VERSION}-amazon-corretto-devel

# Install Maven
echo "Installing Maven $MAVEN_VERSION..."
wget -q https://dlcdn.apache.org/maven/maven-3/$${MAVEN_VERSION}/binaries/apache-maven-$${MAVEN_VERSION}-bin.tar.gz
tar xzf apache-maven-$${MAVEN_VERSION}-bin.tar.gz -C /opt
ln -s /opt/apache-maven-$${MAVEN_VERSION} /opt/maven
rm -f apache-maven-$${MAVEN_VERSION}-bin.tar.gz

# Install Node.js LTS
echo "Installing Node.js $NODEJS_VERSION..."
curl -fsSL https://rpm.nodesource.com/setup_$${NODEJS_VERSION}.x | bash -
dnf install -y nodejs

# Install Ansible (latest)
echo "Installing Ansible..."
pip3 install ansible --quiet

# Install Jenkins CLI (latest)
echo "Installing Jenkins CLI..."
pip3 install jenkins-cli --quiet

# Install eksctl (latest)
echo "Installing eksctl..."
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
chmod +x /usr/local/bin/eksctl

# Install k9s (latest)
echo "Installing k9s..."
curl -sS https://webinstall.dev/k9s | bash
mv ~/.local/bin/k9s /usr/local/bin/ 2>/dev/null || true
chmod +x /usr/local/bin/k9s 2>/dev/null || true

# Install Trivy
echo "Installing Trivy $TRIVY_VERSION..."
rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v$${TRIVY_VERSION}/trivy_$${TRIVY_VERSION}_Linux-64bit.rpm || echo "Trivy installation failed, continuing..."

# Install and configure SSM Agent (pre-installed on AL2023, just ensure it's running)
echo "Configuring SSM Agent..."
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent

# Retrieve package information from SSM Parameter Store
echo "Retrieving package repositories from SSM Parameter Store..."
aws ssm get-parameter --name "/$PROJECT_NAME/packages/devops" --region $AWS_REGION --query 'Parameter.Value' --output text > /tmp/devops-packages.json 2>/dev/null || echo "DevOps packages parameter not found"
aws ssm get-parameter --name "/$PROJECT_NAME/packages/mlops" --region $AWS_REGION --query 'Parameter.Value' --output text > /tmp/mlops-packages.json 2>/dev/null || echo "MLOps packages parameter not found"

# Store package info for reference
if [ -f /tmp/devops-packages.json ]; then
  cp /tmp/devops-packages.json /home/ec2-user/devops-packages.json
  chown ec2-user:ec2-user /home/ec2-user/devops-packages.json
fi

if [ -f /tmp/mlops-packages.json ]; then
  cp /tmp/mlops-packages.json /home/ec2-user/mlops-packages.json
  chown ec2-user:ec2-user /home/ec2-user/mlops-packages.json
fi

# Set environment variables
cat >> /etc/profile.d/devops-tools.sh <<EOF
export JAVA_HOME=/usr/lib/jvm/java-$${JAVA_VERSION}-amazon-corretto
export MAVEN_HOME=/opt/maven
export PATH=\$PATH:\$MAVEN_HOME/bin:\$JAVA_HOME/bin
EOF

# Create tool versions file
cat > /home/ec2-user/tool-versions.txt <<EOF
=== DevOps Tools Installed ===
Docker: $(docker --version)
Docker Compose: $(docker-compose --version)
Kubernetes: $(kubectl version --client --short 2>/dev/null || echo "kubectl installed")
Helm: $(helm version --short)
Terraform: $(terraform version | head -n1)
AWS CLI: $(aws --version)
Python: $(python3 --version)
Java: $(java -version 2>&1 | head -n1)
Maven: $(mvn -version | head -n1)
Node.js: $(node --version)
npm: $(npm --version)
Ansible: $(ansible --version | head -n1)
eksctl: $(eksctl version)
k9s: $(k9s version --short 2>/dev/null || echo "k9s installed")
Trivy: $(trivy --version | head -n1)
Git: $(git --version)
SSM Agent: $(systemctl is-active amazon-ssm-agent)
EOF

chown ec2-user:ec2-user /home/ec2-user/tool-versions.txt

echo "DevOps instance setup completed at $(date)!" | tee /var/log/user-data-complete.log
echo "SUCCESS" > /tmp/user-data-status
