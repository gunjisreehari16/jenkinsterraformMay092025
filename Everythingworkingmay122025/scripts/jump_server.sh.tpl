#!/bin/bash

set -xe

# Update system packages
sudo apt-get update -y
sudo apt-get upgrade -y

# Install common utilities and NGINX
sudo apt-get install -y \
    htop \
    vim \
    git \
    curl \
    wget \
    net-tools \
    unzip \
    tmux \
    fail2ban \
    nginx

# Enable SSH agent forwarding
sudo sed -i 's/^#AllowAgentForwarding.*/AllowAgentForwarding yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Set login banner
echo "Authorized access only. Activity may be monitored and logged." | sudo tee /etc/motd

# Start and enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Jenkins IP injected by Terraform
JENKINS_IP="${JENKINS_IP}"

# Wait for Jenkins to be ready (optional)
for i in {1..20}; do
  if curl -s "http://${JENKINS_IP}:8080/login" > /dev/null; then
    echo "✅ Jenkins is available!"
    break
  fi
  echo "⏳ Waiting for Jenkins at http://${JENKINS_IP}:8080 ..."
  sleep 10
done

# Create NGINX reverse proxy config
cat <<EOF | sudo tee /etc/nginx/sites-available/jenkins > /dev/null
server {
    listen 8080;

    location / {
        proxy_pass http://${JENKINS_IP}:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    access_log /var/log/nginx/jenkins_access.log;
    error_log /var/log/nginx/jenkins_error.log;
}
EOF


# Enable the config and reload NGINX
sudo ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
sudo nginx -t && sudo systemctl reload nginx

echo "✅ NGINX is now proxying Jenkins at http://${JENKINS_IP}"
