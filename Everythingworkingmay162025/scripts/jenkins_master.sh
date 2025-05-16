#!/bin/bash
set -xe

# Wait for network connectivity
timeout=60
elapsed=0
until ping -c1 google.com &>/dev/null || [ $elapsed -ge $timeout ]; do
  echo "🌐 Waiting for network to be available..."
  sleep 5
  elapsed=$((elapsed + 5))
done

# Remount /tmp if it's using tmpfs to avoid space issues
if mount | grep -qE '/tmp type tmpfs'; then
  echo "⚠️ /tmp is on tmpfs. Replacing with disk-backed temp directory..."
  sudo mkdir -p /var/tmp_disk
  sudo chmod 1777 /var/tmp_disk
  sudo mount --bind /var/tmp_disk /tmp
  echo "✅ /tmp is now mounted from /var/tmp_disk"
else
  echo "✅ /tmp is not on tmpfs. No action needed."
fi


# Install Java - check for the preferred versions in order
if sudo yum install -y java-17-amazon-corretto; then
  echo "Amazon Corretto 17 installed successfully."
else
  echo "Failed to install Amazon Corretto 17. Trying OpenJDK 11..."
  if sudo yum install -y java-11-openjdk; then
    echo "OpenJDK 11 installed successfully."
  else
    echo "Failed to install OpenJDK 11. Trying OpenJDK 8..."
    sudo yum install -y java-1.8.0-openjdk-devel || { echo "Failed to install Java, exiting."; exit 1; }
  fi
fi

# Install required packages and dependencies
echo "🔧 Installing required packages and dependencies..."
sudo dnf install -y \
  wget \
  unzip \
  git \
  curl \
  fontconfig \
  gnupg \
  gcc \
  make \
  libxml2-devel || \
  sudo dnf install -y --allowerasing curl

# Install Netcat (nc) if it's not installed
if ! command -v nc &> /dev/null; then
  echo "Netcat (nc) not found, installing..."
  sudo yum install -y nmap-ncat
fi

# Ensure Jenkins user exists
id -u jenkins &>/dev/null || sudo useradd -m -s /bin/bash jenkins

# Add Jenkins repo and updated GPG key
echo "🔐 Adding Jenkins repository..."
sudo curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key -o /etc/pki/rpm-gpg/jenkins.io.key

sudo tee /etc/yum.repos.d/jenkins.repo > /dev/null <<EOF
[Jenkins]
name=Jenkins-stable
baseurl=https://pkg.jenkins.io/redhat-stable
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/jenkins.io.key
enabled=1
EOF

# Clean metadata and install Jenkins
echo "📦 Installing Jenkins..."
sudo dnf clean all
sudo dnf install -y jenkins

# Disable setup wizard (JVM arg)
echo 'JAVA_ARGS="-Djenkins.install.runSetupWizard=false"' | sudo tee /etc/sysconfig/jenkins

# Stop Jenkins before config
sudo systemctl disable --now jenkins

# Init Groovy scripts
sudo mkdir -p /var/lib/jenkins/init.groovy.d

# Admin user Groovy script
echo "🛠️ Configuring Jenkins initial admin user..."
sudo tee /var/lib/jenkins/init.groovy.d/basic-security.groovy > /dev/null <<'EOF'
import jenkins.model.*
import hudson.security.*
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin")
instance.setSecurityRealm(hudsonRealm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
EOF

# Disable setup wizard in Jenkins state
echo "🛠️ Disabling Jenkins setup wizard..."
sudo tee /var/lib/jenkins/init.groovy.d/disable-setup-wizard.groovy > /dev/null <<'EOF'
import jenkins.model.*
import jenkins.install.*
Jenkins.instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
EOF

# Jenkins URL
JENKINS_URL="http://localhost:8080"

# Create slave node
echo "🛠️ Configuring Jenkins slave node..."
sudo tee /var/lib/jenkins/init.groovy.d/create-slave.groovy > /dev/null <<EOF
import jenkins.model.*
import hudson.model.*
import hudson.slaves.*
import hudson.slaves.RetentionStrategy
def instance = Jenkins.getInstance()
JenkinsLocationConfiguration.get().setUrl("http://localhost:8080")
(1).each { i ->
    def name = "slave-\${i}"
    def home = "/home/jenkins-agent-\${i}"
    def launcher = new JNLPLauncher()
    def node = new DumbSlave(name, home, launcher)
    node.setNumExecutors(1)
    node.setMode(Node.Mode.NORMAL)
    node.setLabelString("slave")
    node.setRetentionStrategy(new RetentionStrategy.Always())
    instance.addNode(node)
}
instance.save()
EOF

# Set JNLP port
echo "🛠️ Configuring JNLP port..."
sudo tee /var/lib/jenkins/init.groovy.d/fix-jnlp-port.groovy > /dev/null <<'EOF'
import jenkins.model.Jenkins
Jenkins.instance.setSlaveAgentPort(50000)
Jenkins.instance.save()
EOF

# Set executors and URL
echo "🛠️ Configuring Jenkins executors and URL..."
sudo tee /var/lib/jenkins/init.groovy.d/set-executors-and-url.groovy > /dev/null <<EOF
import jenkins.model.*
def instance = Jenkins.getInstance()
instance.setNumExecutors(2)
JenkinsLocationConfiguration.get().setUrl("${JENKINS_URL}")
instance.save()
EOF

# Marker files
echo "2.440" | sudo tee /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
echo "2.440" | sudo tee /var/lib/jenkins/jenkins.install.UpgradeWizard.state

# Fix permissions
echo "🛠️ Fixing Jenkins directory permissions..."
sudo chown -R jenkins:jenkins /var/lib/jenkins

# Start Jenkins
echo "🚀 Starting Jenkins..."
sudo systemctl enable --now jenkins

# Wait for Jenkins to initialize
timeout=300
elapsed=0
until nc -z localhost 8080 || [ $elapsed -ge $timeout ]; do
  echo "⏳ Waiting for Jenkins to start..."
  sleep 10
  elapsed=$((elapsed + 10))
done

# Wait for Jenkins API
elapsed=0
until curl -s -u admin:admin http://localhost:8080/api/json | grep -q '"mode"' || [ $elapsed -ge $timeout ]; do
  echo "⌛ Jenkins API not ready yet..."
  sleep 10
  elapsed=$((elapsed + 10))
done

# Ensure the update center is initialized
echo "🔄 Ensuring Jenkins update center is initialized..."
curl -s -u admin:admin http://localhost:8080/updateCenter/initialization

# Download CLI and agent jars
cli_timeout=180
cli_elapsed=0
while [ $cli_elapsed -lt $cli_timeout ]; do
  if curl -sLo /var/lib/jenkins/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar; then
    break
  fi
  echo "⏳ Waiting for CLI jar to download..."
  sleep 5
  cli_elapsed=$((cli_elapsed + 5))
done

curl -sLo /var/lib/jenkins/agent.jar http://localhost:8080/jnlpJars/agent.jar
sudo ln -sf /var/lib/jenkins/jenkins-cli.jar /usr/local/bin/jenkins-cli.jar
sudo chown jenkins:jenkins /var/lib/jenkins/jenkins-cli.jar

# Plugin installation with retry
echo "🔌 Installing Jenkins plugins..."
PLUGIN_LIST="git-client git github-api github-oauth github ssh-slaves workflow-aggregator ws-cleanup matrix-auth"
for plugin in $PLUGIN_LIST; do
  echo "🔌 Installing plugin: $plugin"
  retry=0
  until java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin install-plugin "$plugin" -deploy || [ $retry -ge 5 ]; do
    echo "🔁 Retry installing $plugin..."
    sleep 5
    retry=$((retry + 1))
  done
done

# Ensure plugin dependencies are resolved
echo "📦 Ensuring all plugin dependencies are resolved..."
java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin install-plugin $(java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin list-plugins | grep -i '\[failed\]' | cut -d ' ' -f1) -deploy || true

# Safe restart Jenkins
echo "♻️ Restarting Jenkins..."
java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin safe-restart

# Wait for Jenkins to come back
restart_timeout=300
restart_elapsed=0
until nc -z localhost 8080 || [ $restart_elapsed -ge $restart_timeout ]; do
  echo "⏳ Waiting for Jenkins to restart..."
  sleep 10
  restart_elapsed=$((restart_elapsed + 10))
done

# Optional cleanup
echo "🧹 Cleaning up temporary files..."
sudo rm -rf /tmp/*
sudo yum clean all

echo "✅ Jenkins setup completed successfully!"
