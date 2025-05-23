# Git_lab Server (public subnet)
resource "aws_instance" "gitlab_server" {
  ami                         = var.gitlab_ami
  instance_type               = var.gitlab_instance_type
  subnet_id                   = aws_subnet.vzrsp_cicd_public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.gitlab_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  user_data                   = file("scripts/gitlab_install.sh")

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "Git_lab Server"
  }
}
