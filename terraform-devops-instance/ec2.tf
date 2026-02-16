data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "devops" {
  count                  = var.instance_count
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.devops.id]
  iam_instance_profile   = aws_iam_instance_profile.devops.name
  key_name               = aws_key_pair.devops.key_name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    terraform_version = var.terraform_version
    maven_version     = var.maven_version
    nodejs_version    = var.nodejs_version
    python_version    = var.python_version
    java_version      = var.java_version
    trivy_version     = var.trivy_version
    project_name      = var.project_name
    aws_region        = var.aws_region
  }))

  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-instance-${count.index + 1}"
  }
}
