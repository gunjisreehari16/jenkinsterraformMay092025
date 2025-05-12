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
