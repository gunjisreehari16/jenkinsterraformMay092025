# IAM Role for Jenkins Master
resource "aws_iam_role" "jenkins_master_role" {
  name = "jenkins-master-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM Policy to access SSM Parameter
resource "aws_iam_policy" "jenkins_master_ssm_policy" {
  name = "jenkins-master-ssm-policy"

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

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "jenkins_master_policy_attach" {
  role       = aws_iam_role.jenkins_master_role.name
  policy_arn = aws_iam_policy.jenkins_master_ssm_policy.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "jenkins_master_instance_profile" {
  name = "jenkins-master-instance-profile"
  role = aws_iam_role.jenkins_master_role.name
}

# Jenkins Master EC2 Instance
resource "aws_instance" "jenkins_master" {
  ami                         = var.jenkins_ami
  instance_type               = var.jenkins_master_instance_type
  subnet_id                   = aws_subnet.vzrsp_cicd_private_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name
  user_data                   = file("scripts/jenkins_master.sh")

  iam_instance_profile        = aws_iam_instance_profile.jenkins_master_instance_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins Master"
  }
}
