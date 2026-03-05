# ============================================
# TERRAFORM PROVISIONERS - Complete Examples
# ============================================
# NOTE: Provisioners are a last resort!
# Prefer cloud-init, user_data, or config management tools

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "ssh_private_key_path" {
  default = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  default = "ec2-user"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ============================================
# LOCAL-EXEC PROVISIONER
# ============================================
# Runs commands on the machine running Terraform

resource "aws_instance" "local_exec_example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "local-exec-example"
  }

  # Run after creation
  provisioner "local-exec" {
    command = "echo 'Instance ${self.id} created at ${self.public_ip}' >> instances.log"
  }

  # Run with different interpreter
  provisioner "local-exec" {
    command     = "Write-Output 'Created instance ${self.id}'"
    interpreter = ["PowerShell", "-Command"]
    when        = create
  }

  # Run with environment variables
  provisioner "local-exec" {
    command = "echo $INSTANCE_ID >> instances.log"
    environment = {
      INSTANCE_ID = self.id
    }
  }

  # Run on destroy
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Instance ${self.id} destroyed' >> instances.log"
  }
}

# ============================================
# REMOTE-EXEC PROVISIONER
# ============================================
# Runs commands on the remote resource via SSH/WinRM

resource "aws_instance" "remote_exec_example" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "my-key-pair"  # Must exist
  vpc_security_group_ids = [aws_security_group.ssh.id]

  tags = {
    Name = "remote-exec-example"
  }

  # Connection block defines how to connect
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = self.public_ip
    timeout     = "5m"
  }

  # Inline commands
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y httpd",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "echo '<h1>Hello from Terraform</h1>' | sudo tee /var/www/html/index.html"
    ]
  }

  # Or run a script
  # provisioner "remote-exec" {
  #   script = "scripts/setup.sh"
  # }

  # Or run multiple scripts
  # provisioner "remote-exec" {
  #   scripts = [
  #     "scripts/install.sh",
  #     "scripts/configure.sh"
  #   ]
  # }
}

# ============================================
# FILE PROVISIONER
# ============================================
# Copies files/directories to the resource

resource "aws_instance" "file_example" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "my-key-pair"
  vpc_security_group_ids = [aws_security_group.ssh.id]

  tags = {
    Name = "file-example"
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = self.public_ip
  }

  # Copy single file
  provisioner "file" {
    source      = "configs/app.conf"
    destination = "/tmp/app.conf"
  }

  # Copy directory
  provisioner "file" {
    source      = "configs/"  # Trailing slash = contents only
    destination = "/tmp/configs"
  }

  # Copy from content (no source file needed)
  provisioner "file" {
    content     = "DATABASE_URL=postgres://user:pass@host:5432/db"
    destination = "/tmp/.env"
  }

  # Then run commands to use the files
  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/app.conf /etc/app/app.conf",
      "sudo chmod 644 /etc/app/app.conf"
    ]
  }
}

# ============================================
# ERROR HANDLING
# ============================================

resource "aws_instance" "with_error_handling" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "error-handling-example"
  }

  # Continue on failure (not recommended for critical steps)
  provisioner "local-exec" {
    command    = "exit 1"  # This will fail
    on_failure = continue  # But won't stop the apply
  }

  # Fail on error (default behavior)
  provisioner "local-exec" {
    command    = "echo 'This runs after the failed command'"
    on_failure = fail  # Default
  }
}

# ============================================
# NULL RESOURCE WITH PROVISIONER
# ============================================
# Run provisioners without creating real resources

resource "null_resource" "run_ansible" {
  # Triggers define when to re-run
  triggers = {
    instance_id = aws_instance.local_exec_example.id
    always_run  = timestamp()  # Re-run every apply
  }

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i '${aws_instance.local_exec_example.public_ip},' \
        --private-key ${var.ssh_private_key_path} \
        playbooks/configure.yml
    EOT
  }

  depends_on = [aws_instance.local_exec_example]
}

# ============================================
# SUPPORTING RESOURCES
# ============================================

resource "aws_security_group" "ssh" {
  name        = "allow-ssh"
  description = "Allow SSH inbound"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ============================================
# BEST PRACTICES
# ============================================

# 1. AVOID PROVISIONERS when possible
#    - Use cloud-init/user_data for EC2
#    - Use Packer for pre-built images
#    - Use configuration management (Ansible, Chef, Puppet)

# 2. If you must use provisioners:
#    - Make them idempotent
#    - Handle errors gracefully
#    - Use null_resource for re-runnable tasks
#    - Keep scripts in version control

# 3. For Kubernetes/containers:
#    - Use init containers
#    - Use ConfigMaps and Secrets
#    - Don't use provisioners!

# ============================================
# ALTERNATIVE: USER_DATA (PREFERRED)
# ============================================

resource "aws_instance" "user_data_example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo '<h1>Hello from Terraform</h1>' > /var/www/html/index.html
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "user-data-example"
  }
}

# ============================================
# OUTPUTS
# ============================================

output "local_exec_instance_id" {
  value = aws_instance.local_exec_example.id
}

output "user_data_public_ip" {
  value = aws_instance.user_data_example.public_ip
}
