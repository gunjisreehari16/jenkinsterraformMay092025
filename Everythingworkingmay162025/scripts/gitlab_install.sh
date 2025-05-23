#!/bin/bash
set -e

# Timeout wrapper
timeout_cmd() {
  local timeout_duration=$1
  shift
  timeout --foreground "$timeout_duration" "$@"
}

# Settings
TIMEOUT="300s"  # 5 min timeout
GITLAB_SCRIPT="/tmp/gitlab_install.sh"
GITLAB_PACKAGE_URL="https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh"

# Fetch external IP using http://checkip.amazonaws.com
echo "🌐 Fetching public IP from http://checkip.amazonaws.com..."
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ Could not determine public IP. Aborting."
  exit 1
fi

EXTERNAL_URL="http://$PUBLIC_IP"
echo "✅ Detected external URL: $EXTERNAL_URL"

# Update system
echo "📦 Updating system..."
timeout_cmd "$TIMEOUT" dnf update -y

# Install dependencies
echo "📦 Installing required packages..."
timeout_cmd "$TIMEOUT" dnf install -y policycoreutils openssh-server perl firewalld



# Download GitLab repo installer
echo "📥 Downloading GitLab repo setup script..."
timeout_cmd "$TIMEOUT" wget -q "$GITLAB_PACKAGE_URL" -O "$GITLAB_SCRIPT"

# Run GitLab repo installer
echo "⚙️ Running GitLab repo script..."
timeout_cmd "$TIMEOUT" bash "$GITLAB_SCRIPT"

# Install GitLab CE
echo "📦 Installing GitLab CE..."
timeout_cmd "$TIMEOUT" dnf install -y gitlab-ce

# Set external URL
echo "🌍 Setting GitLab external URL..."
echo "external_url '$EXTERNAL_URL'" > /etc/gitlab/gitlab.rb

# Kill anything on port 80 before reconfigure
echo "🛑 Checking and clearing port 80 usage..."
fuser -k 80/tcp || true

# Reconfigure GitLab with timeout and fallback
echo "🔧 Running gitlab-ctl reconfigure..."
if ! timeout_cmd "$TIMEOUT" gitlab-ctl reconfigure; then
  echo "⚠️ gitlab-ctl reconfigure failed or hung. Attempting manual service recovery..."

  echo "🔁 Restarting gitlab-runsvdir manually with timeout..."
  if ! timeout_cmd 60s systemctl restart gitlab-runsvdir; then
    echo "❌ Failed to start gitlab-runsvdir. Dumping journal logs:"
    journalctl -u gitlab-runsvdir --no-pager | tail -n 30
    exit 1
  fi

  echo "🔁 Restarting nginx manually..."
  if ! gitlab-ctl restart nginx; then
    echo "❌ Failed to restart nginx. Dumping logs:"
    gitlab-ctl tail nginx
    exit 1
  fi
fi

# Restart all GitLab services
echo "🔁 Restarting all GitLab services..."
timeout_cmd "$TIMEOUT" gitlab-ctl restart

# Final success message
echo "✅ GitLab installed successfully!"
echo "🌐 Access it at: $EXTERNAL_URL"

# Verify accessibility
echo "🔎 Checking GitLab accessibility..."
if timeout_cmd 60s wget -q --spider "$EXTERNAL_URL"; then
  echo "✅ GitLab is accessible at $EXTERNAL_URL"
else
  echo "❌ GitLab is not accessible at $EXTERNAL_URL. Please verify security groups, firewall rules, and DNS settings."
fi
