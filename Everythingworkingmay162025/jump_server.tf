# Jump Server Instance (public subnet)
resource "aws_instance" "jump_server" {
  ami                         = var.jump_server_ami
  instance_type               = var.jump_server_instance_type
  subnet_id                   = aws_subnet.vzrsp_cicd_public_subnet[0].id
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
  depends_on = [aws_internet_gateway.vzrsp_cicd_igw]

  tags = {
    Name = "Jump Server EIP"
  }
}
