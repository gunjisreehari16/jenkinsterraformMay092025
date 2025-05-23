#!/bin/bash

set -xe

# Update system packages
echo "🔄 Updating system packages..."
sudo yum update -y || { echo "Failed to update system packages, exiting."; exit 1; }

# Check if curl-minimal is installed and if there is a conflict with curl
echo "🔧 Resolving curl conflict..."
if sudo yum list installed curl-minimal > /dev/null 2>&1; then
  echo "curl-minimal is installed, skipping removal."
else
  echo "curl-minimal is not installed."
fi

# Install curl using --allowerasing to replace any conflicting packages
echo "🔧 Installing curl..."
if sudo yum install -y curl --allowerasing; then
  echo "curl installed successfully."
else
  echo "Failed to install curl, exiting."
  exit 1
fi

# Install common utilities and NGINX
echo "⚙️ Installing common utilities and NGINX..."
if sudo yum install -y \
    htop \
    vim \
    git \
    wget \
    unzip \
    tmux \
    nginx; then
  echo "Utilities and NGINX installed successfully."
else
  echo "Failed to install utilities and NGINX, exiting."
  exit 1
fi

# Optional: Install fail2ban manually if needed (not available in default repos)
# echo "⚙️ Installing fail2ban..."
# sudo yum install -y fail2ban || { echo "Failed to install fail2ban."; }

# Enable SSH agent forwarding
echo "🔐 Enabling SSH agent forwarding..."
if sudo sed -i 's/^#AllowAgentForwarding.*/AllowAgentForwarding yes/' /etc/ssh/sshd_config; then
  echo "SSH agent forwarding enabled."
  sudo systemctl restart sshd
else
  echo "Failed to enable SSH agent forwarding."
  exit 1
fi

# Set login banner
echo "Authorized access only. Activity may be monitored and logged." | sudo tee /etc/motd

# Start and enable NGINX
echo "🚀 Starting and enabling NGINX..."
if sudo systemctl enable nginx && sudo systemctl start nginx; then
  echo "NGINX started and enabled successfully."
else
  echo "Failed to start or enable NGINX, exiting."
  exit 1
fi

# Jenkins IP injected by Terraform or passed as an environment variable
JENKINS_IP="${JENKINS_IP}"

# Wait for Jenkins to be ready (optional)
echo "⏳ Waiting for Jenkins to be available at http://${JENKINS_IP}:8080 ..."
count=0
MAX_RETRIES=20
until curl -s "http://${JENKINS_IP}:8080/login" > /dev/null; do
  count=$((count+1))
  if [ "$count" -ge "$MAX_RETRIES" ]; then
    echo "❌ Jenkins is not available after $MAX_RETRIES attempts."
    exit 1
  fi
  echo "⏳ Still waiting for Jenkins... Attempt $count of $MAX_RETRIES"
  sleep 10
done

echo "✅ Jenkins is available!"

# Create NGINX reverse proxy config
echo "🔧 Creating NGINX reverse proxy configuration..."
cat <<EOF | sudo tee /etc/nginx/conf.d/jenkins.conf > /dev/null
server {
    listen 8080;

    location / {
        proxy_pass http://${JENKINS_IP}:8080;  # Pass to the correct internal Jenkins IP/port

        # Important headers to pass through
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Ssl on;  # If using SSL

        proxy_http_version 1.1;
        proxy_request_buffering off;
    }

    access_log /var/log/nginx/jenkins_access.log;
    error_log /var/log/nginx/jenkins_error.log;
}
EOF

# Reload NGINX
echo "🔄 Testing NGINX config and reloading..."
if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "✅ NGINX successfully reloaded."
else
  echo "❌ NGINX configuration failed. Please check the error logs."
  exit 1
fi

echo "✅ NGINX is now proxying Jenkins at http://${JENKINS_IP}:8080"
