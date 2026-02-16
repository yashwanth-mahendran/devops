resource "tls_private_key" "devops" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "devops" {
  key_name   = var.key_name
  public_key = tls_private_key.devops.public_key_openssh

  tags = {
    Name = "${var.project_name}-keypair"
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.devops.private_key_pem
  filename        = "${path.module}/${var.key_name}.pem"
  file_permission = "0400"
}
