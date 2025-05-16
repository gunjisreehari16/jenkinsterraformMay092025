# VPC
resource "aws_vpc" "vzrsp_cicd_vpc" {
  cidr_block = var.vpc_cidr
  tags       = { Name = "vzrsp-cicd-vpc" }
}

# Public Subnets
resource "aws_subnet" "vzrsp_cicd_public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.vzrsp_cicd_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "vzrsp-cicd-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "vzrsp_cicd_private_subnet" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.vzrsp_cicd_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "vzrsp-cicd-private-subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "vzrsp_cicd_igw" {
  vpc_id = aws_vpc.vzrsp_cicd_vpc.id
  tags   = { Name = "vzrsp-cicd-igw" }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "vzrsp_cicd_nat_eip" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "vzrsp_cicd_nat" {
  allocation_id = aws_eip.vzrsp_cicd_nat_eip.id
  subnet_id     = aws_subnet.vzrsp_cicd_public_subnet[0].id
  depends_on    = [aws_internet_gateway.vzrsp_cicd_igw]
  tags          = { Name = "vzrsp-cicd-nat-gateway" }
}

# Public Route Table
resource "aws_route_table" "vzrsp_cicd_public_rt" {
  vpc_id = aws_vpc.vzrsp_cicd_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vzrsp_cicd_igw.id
  }

  tags = { Name = "vzrsp-cicd-public-rt" }
}

resource "aws_route_table_association" "vzrsp_cicd_public_assoc" {
  count          = length(aws_subnet.vzrsp_cicd_public_subnet)
  subnet_id      = aws_subnet.vzrsp_cicd_public_subnet[count.index].id
  route_table_id = aws_route_table.vzrsp_cicd_public_rt.id
}

# Private Route Table
resource "aws_route_table" "vzrsp_cicd_private_rt" {
  vpc_id = aws_vpc.vzrsp_cicd_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.vzrsp_cicd_nat.id
  }

  tags = { Name = "vzrsp-cicd-private-rt" }
}

resource "aws_route_table_association" "vzrsp_cicd_private_assoc" {
  count          = length(aws_subnet.vzrsp_cicd_private_subnet)
  subnet_id      = aws_subnet.vzrsp_cicd_private_subnet[count.index].id
  route_table_id = aws_route_table.vzrsp_cicd_private_rt.id
}
