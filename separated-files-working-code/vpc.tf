resource "aws_vpc" "RSP_IOT_vpc" {
  cidr_block = var.vpc_cidr
  tags       = { Name = "RSP-IOT" }
}

resource "aws_subnet" "RSP_IOT_public_subnet" {
  vpc_id                  = aws_vpc.RSP_IOT_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags                    = { Name = "RSP-IOT Public Subnet" }
}

resource "aws_subnet" "RSP_IOT_private_subnet" {
  vpc_id                  = aws_vpc.RSP_IOT_vpc.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "RSP-IOT Private Subnet" }
}

resource "aws_internet_gateway" "RSP_IOT_igw" {
  vpc_id = aws_vpc.RSP_IOT_vpc.id
  tags   = { Name = "RSP-IOT-IGW" }
}

resource "aws_eip" "RSP_IOT_nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "RSP_IOT_nat" {
  allocation_id = aws_eip.RSP_IOT_nat_eip.id
  subnet_id     = aws_subnet.RSP_IOT_public_subnet.id
  depends_on    = [aws_internet_gateway.RSP_IOT_igw]
  tags          = { Name = "RSP-IOT-NAT-Gateway" }
}

resource "aws_route_table" "RSP_IOT_public_rt" {
  vpc_id = aws_vpc.RSP_IOT_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.RSP_IOT_igw.id
  }

  tags = { Name = "RSP-IOT Public Route Table" }
}

resource "aws_route_table_association" "RSP_IOT_public_assoc" {
  subnet_id      = aws_subnet.RSP_IOT_public_subnet.id
  route_table_id = aws_route_table.RSP_IOT_public_rt.id
}

resource "aws_route_table" "RSP_IOT_private_rt" {
  vpc_id = aws_vpc.RSP_IOT_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.RSP_IOT_nat.id
  }

  tags = { Name = "RSP-IOT Private Route Table" }
}

resource "aws_route_table_association" "RSP_IOT_private_assoc" {
  subnet_id      = aws_subnet.RSP_IOT_private_subnet.id
  route_table_id = aws_route_table.RSP_IOT_private_rt.id
}
