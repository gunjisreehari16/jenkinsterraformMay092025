output "jenkins_slave_private_ips" {
  description = "Private IPs of Jenkins slave nodes"
  value       = [for instance in aws_instance.Jenkins_slave : instance.private_ip]
}

# Jump Server Public IP
output "jump_server_public_ip" {
  description = "Public IP of the Jump Server"
  value       = aws_eip.jump_server_eip.public_ip
}

# Jenkins Master Private IP
output "jenkins_master_private_ip" {
  description = "Private IP of the Jenkins Master"
  value       = aws_instance.jenkins_master.private_ip
}
