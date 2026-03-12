################################################################################
# Data Sources
################################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

################################################################################
# Public Subnets (ALB, NAT Gateway)
################################################################################

resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false  # Security: No auto-assign public IP

  tags = {
    Name                                        = "${var.project_name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "public"
  }
}

################################################################################
# Private Subnets (EKS Nodes, Application Pods)
################################################################################

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 16)
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.project_name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "private"
  }
}

################################################################################
# Isolated Subnets (VPC Endpoints Only - No Internet Access)
################################################################################

resource "aws_subnet" "isolated" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 32)
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-isolated-${local.azs[count.index]}"
    Tier = "isolated"
  }
}
