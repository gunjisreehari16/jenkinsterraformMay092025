# IAM Role for Jenkins Slave
resource "aws_iam_role" "jenkins_slave_role" {
  name = "jenkins-slave-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM Policy to allow SSM Parameter read for slaves
resource "aws_iam_policy" "jenkins_slave_ssm_policy" {
  name = "jenkins-slave-ssm-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "ssm:GetParameter",
        Resource = "arn:aws:ssm:*:*:parameter/jenkins/admin_password"
      }
    ]
  })
}

# Attach policy to slave role
resource "aws_iam_role_policy_attachment" "jenkins_slave_policy_attach" {
  role       = aws_iam_role.jenkins_slave_role.name
  policy_arn = aws_iam_policy.jenkins_slave_ssm_policy.arn
}

# Instance Profile for slaves
resource "aws_iam_instance_profile" "jenkins_slave_instance_profile" {
  name = "jenkins-slave-instance-profile"
  role = aws_iam_role.jenkins_slave_role.name
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

resource "aws_instance" "jenkins_slave" {
  count                       = var.jenkins_slave_count
  ami                         = var.jenkins_ami
  instance_type               = var.jenkins_slave_instance_type
  subnet_id                   = aws_subnet.vzrsp_cicd_private_subnet[count.index % length(var.private_subnet_cidrs)].id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  user_data                   = data.template_file.slave_user_data[count.index].rendered
  depends_on                  = [aws_instance.jenkins_master, aws_nat_gateway.vzrsp_cicd_nat]

  iam_instance_profile        = aws_iam_instance_profile.jenkins_slave_instance_profile.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins Slave-${count.index + 1}"
  }
}
