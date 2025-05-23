output "jenkins_slave_private_ips" {
  description = "Private IPs of Jenkins slave nodes"
  value       = [for instance in aws_instance.jenkins_slave : instance.private_ip]
}

output "jump_server_public_ip" {
  description = "Public IP of the Jump Server"
  value       = aws_eip.jump_server_eip.public_ip
}

output "jenkins_master_private_ip" {
  description = "Private IP of the Jenkins Master"
  value       = aws_instance.jenkins_master.private_ip
}

output "gitlab_public_ip" {
  value = aws_instance.gitlab_server.public_ip
}

output "gitlab_root_user" {
  description = "GitLab root username"
  value       = "root"
}

output "gitlab_initial_root_password_location" {
  description = "Location of the initial GitLab root password on the server"
  value       = "/etc/gitlab/initial_root_password (use sudo cat to retrieve)"
}

output "jenkins_username" {
  description = "Jenkins admin username"
  value       = "admin"
}

output "jenkins_password" {
  description = "Jenkins admin password"
  value       = "admin@123"
}
