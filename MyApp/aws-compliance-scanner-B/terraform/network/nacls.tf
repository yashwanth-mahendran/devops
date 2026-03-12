################################################################################
# Public Subnet NACL
################################################################################

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-public-nacl"
  }
}

# Deny SSH from Internet (explicit)
resource "aws_network_acl_rule" "public_deny_ssh" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 50
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 22
  to_port        = 22
}

# Deny RDP from Internet (explicit)
resource "aws_network_acl_rule" "public_deny_rdp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 51
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 3389
  to_port        = 3389
}

# Allow HTTPS inbound
resource "aws_network_acl_rule" "public_allow_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Allow HTTP inbound (for redirect)
resource "aws_network_acl_rule" "public_allow_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Allow ephemeral inbound (return traffic)
resource "aws_network_acl_rule" "public_allow_ephemeral_in" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Allow all outbound
resource "aws_network_acl_rule" "public_allow_all_egress" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

################################################################################
# Private Subnet NACL
################################################################################

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-private-nacl"
  }
}

# Deny SSH from public subnets (defense in depth)
resource "aws_network_acl_rule" "private_deny_ssh" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 50
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = cidrsubnet(var.vpc_cidr, 4, 0)  # Public subnet range
  from_port      = 22
  to_port        = 22
}

# Allow all from VPC
resource "aws_network_acl_rule" "private_allow_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}

# Allow ephemeral inbound (return traffic from NAT)
resource "aws_network_acl_rule" "private_allow_ephemeral_in" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Allow all outbound
resource "aws_network_acl_rule" "private_allow_all_egress" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

################################################################################
# Isolated Subnet NACL (VPC Endpoints Only)
################################################################################

resource "aws_network_acl" "isolated" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.isolated[*].id

  tags = {
    Name = "${var.project_name}-isolated-nacl"
  }
}

# Allow HTTPS from VPC only (for VPC endpoints)
resource "aws_network_acl_rule" "isolated_allow_https" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 443
  to_port        = 443
}

# Allow ephemeral from VPC
resource "aws_network_acl_rule" "isolated_allow_ephemeral" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

# DENY all from Internet (explicit)
resource "aws_network_acl_rule" "isolated_deny_internet" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 999
  egress         = false
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# Allow outbound to VPC only
resource "aws_network_acl_rule" "isolated_allow_vpc_egress" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}
