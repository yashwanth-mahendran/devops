################################################################################
# Elastic IPs for NAT Gateway (one per AZ for HA)
################################################################################

resource "aws_eip" "nat" {
  count  = var.enable_ha_nat ? length(local.azs) : 1
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

################################################################################
# NAT Gateways (Multi-AZ for High Availability)
################################################################################

resource "aws_nat_gateway" "main" {
  count         = var.enable_ha_nat ? length(local.azs) : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}
