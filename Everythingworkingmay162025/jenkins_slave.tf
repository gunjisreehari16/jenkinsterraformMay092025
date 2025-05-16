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
  subnet_id                   = aws_subnet.vzrsp_cicd_private_subnet[count.index % length(var.private_subnet_cidrs)].id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  user_data                   = data.template_file.slave_user_data[count.index].rendered
  depends_on                  = [aws_instance.jenkins_master, aws_nat_gateway.vzrsp_cicd_nat]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins Slave-${count.index + 1}"
  }
}
