provider "aws" {
  region = var.region
}

# VPC and Subnets
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

# Internet Gateway and NAT Gateway
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

# Route Tables for Public and Private Subnets
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

# Security Group for Jenkins
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  vpc_id      = aws_vpc.RSP_IOT_vpc.id
  description = "Allow Jenkins traffic"

  # SSH access from Jump Server only
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jump_sg.id]
  }

  # HTTP for Jenkins web UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins slave communication
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internal communication within VPC
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

# Jenkins Master (private subnet)
resource "aws_instance" "jenkins_master" {
  ami                         = var.jenkins_ami
  instance_type               = var.jenkins_master_instance_type
  subnet_id                   = aws_subnet.RSP_IOT_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  user_data                   = file("scripts/jenkins_master.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins Master"
  }
}

# Jenkins Slaves (scaled based on count)
data "template_file" "slave_user_data" {
  count    = var.jenkins_slave_count
  template = file("scripts/jenkins_slave.sh.tpl")

  vars = {
    jenkins_url = "http://${aws_instance.jenkins_master.private_ip}:8080"
    slave_name  = "slave-${count.index + 1}"
  }
}

resource "aws_instance" "Jenkins_slave" {
  count                       = var.jenkins_slave_count
  ami                         = var.jenkins_ami
  instance_type               = var.jenkins_slave_instance_type
  subnet_id                   = aws_subnet.RSP_IOT_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  user_data                   = data.template_file.slave_user_data[count.index].rendered
  depends_on                  = [aws_instance.jenkins_master, aws_nat_gateway.RSP_IOT_nat]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins Slave-${count.index + 1}"
  }
}

# Security Group for Jump Server
resource "aws_security_group" "jump_sg" {
  name        = "jump-server-sg"
  vpc_id      = aws_vpc.RSP_IOT_vpc.id
  description = "Allow SSH from internet and access to private subnet"

  # SSH access from the internet (use restricted IP range for better security)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 
  }
    ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jump-server-sg" }
}

# Jump Server Instance (public subnet)
resource "aws_instance" "jump_server" {
  ami                         = var.jump_server_ami
  instance_type               = var.jump_server_instance_type
  subnet_id                   = aws_subnet.RSP_IOT_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.jump_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  user_data = templatefile("scripts/jump_server.sh.tpl", {
  JENKINS_IP = aws_instance.jenkins_master.private_ip
})

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  

  tags = {
    Name = "Jump Server"
  }
}

# EIP for Jump Server
resource "aws_eip" "jump_server_eip" {
  domain     = "vpc"
  instance   = aws_instance.jump_server.id
  depends_on = [aws_internet_gateway.RSP_IOT_igw]
}


