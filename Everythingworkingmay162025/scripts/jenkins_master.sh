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

# Retrieve the public IP of the Jump Server (dynamically)
JUMP_SERVER_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Securely fetch Jenkins admin password from AWS SSM Parameter Store
JENKINS_PASSWORD=$(aws ssm get-parameter --name "/jenkins/admin_password" --with-decryption --query "Parameter.Value" --output text)

# Remount /tmp if it's using tmpfs
if mount | grep -qE '/tmp type tmpfs'; then
  echo "⚠️ /tmp is on tmpfs. Replacing with disk-backed temp directory..."
  sudo mkdir -p /var/tmp_disk
  sudo chmod 1777 /var/tmp_disk
  sudo mount --bind /var/tmp_disk /tmp
  echo "✅ /tmp is now mounted from /var/tmp_disk"
else
  echo "✅ /tmp is not on tmpfs. No action needed."
fi

# Install Java (preferring Amazon Corretto)
if sudo yum install -y java-21-amazon-corretto; then
  echo "Amazon Corretto 21 installed successfully."
else
  echo "Failed to install Amazon Corretto 21. Trying OpenJDK 11..."
  if sudo yum install -y java-11-openjdk; then
    echo "OpenJDK 11 installed successfully."
  else
    echo "Failed to install OpenJDK 11. Trying OpenJDK 8..."
    sudo yum install -y java-1.8.0-openjdk-devel || { echo "Failed to install Java, exiting."; exit 1; }
  fi
fi

# Install dependencies
sudo dnf install -y wget unzip git curl fontconfig gnupg gcc make libxml2-devel || sudo dnf install -y --allowerasing curl

# Install Netcat
if ! command -v nc &> /dev/null; then
  sudo yum install -y nmap-ncat
fi

# Ensure Jenkins user exists
id -u jenkins &>/dev/null || sudo useradd -m -s /bin/bash jenkins

# Jenkins repo and key
sudo curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key -o /etc/pki/rpm-gpg/jenkins.io.key

sudo tee /etc/yum.repos.d/jenkins.repo > /dev/null <<EOF
[Jenkins]
name=Jenkins-stable
baseurl=https://pkg.jenkins.io/redhat-stable
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/jenkins.io.key
enabled=1
EOF

# Install Jenkins
sudo dnf clean all
sudo dnf install -y jenkins
echo 'JAVA_ARGS="-Djenkins.install.runSetupWizard=false"' | sudo tee /etc/sysconfig/jenkins
sudo systemctl disable --now jenkins

# Setup Groovy scripts
sudo mkdir -p /var/lib/jenkins/init.groovy.d

# Create Jenkins admin user securely
sudo tee /var/lib/jenkins/init.groovy.d/basic-security.groovy > /dev/null <<EOF
import jenkins.model.*
import hudson.security.*
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "${JENKINS_PASSWORD}")
instance.setSecurityRealm(hudsonRealm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
EOF

# Disable setup wizard
sudo tee /var/lib/jenkins/init.groovy.d/disable-setup-wizard.groovy > /dev/null <<'EOF'
import jenkins.model.*
import jenkins.install.*
Jenkins.instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
EOF

# Dynamically set Jenkins URL using Jump Server public IP (or reverse proxy URL)
JENKINS_URL="http://${JUMP_SERVER_PUBLIC_IP}:8080"

# Create slave node
sudo tee /var/lib/jenkins/init.groovy.d/create-slave.groovy > /dev/null <<EOF
import jenkins.model.*
import hudson.model.*
import hudson.slaves.*
import hudson.slaves.RetentionStrategy
def instance = Jenkins.getInstance()
JenkinsLocationConfiguration.get().setUrl("${JENKINS_URL}")
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

# JNLP port
sudo tee /var/lib/jenkins/init.groovy.d/fix-jnlp-port.groovy > /dev/null <<'EOF'
import jenkins.model.Jenkins
Jenkins.instance.setSlaveAgentPort(50000)
Jenkins.instance.save()
EOF

# Set Jenkins URL and executor count
sudo tee /var/lib/jenkins/init.groovy.d/set-executors-and-url.groovy > /dev/null <<EOF
import jenkins.model.*
def instance = Jenkins.getInstance()
instance.setNumExecutors(2)
JenkinsLocationConfiguration.get().setUrl("${JENKINS_URL}")
instance.save()
EOF

# Install marker
echo "2.440" | sudo tee /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
echo "2.440" | sudo tee /var/lib/jenkins/jenkins.install.UpgradeWizard.state

# Fix permissions
sudo chown -R jenkins:jenkins /var/lib/jenkins

# Start Jenkins
sudo systemctl enable --now jenkins

# Wait for Jenkins to start
timeout=300
elapsed=0
until nc -z localhost 8080 || [ $elapsed -ge $timeout ]; do
  echo "⏳ Waiting for Jenkins to start..."
  sleep 10
  elapsed=$((elapsed + 10))
done

# Wait for Jenkins API
elapsed=0
until curl -s -u admin:$JENKINS_PASSWORD http://localhost:8080/api/json | grep -q '"mode"' || [ $elapsed -ge $timeout ]; do
  echo "⌛ Jenkins API not ready yet..."
  sleep 10
  elapsed=$((elapsed + 10))
done

# Initialize update center
curl -s -u admin:$JENKINS_PASSWORD http://localhost:8080/updateCenter/initialization

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

# Install Jenkins plugins
PLUGIN_LIST="git-client git github-api github-oauth github ssh-slaves workflow-aggregator ws-cleanup matrix-auth maven-plugin gradle"
for plugin in $PLUGIN_LIST; do
  retry=0
  until java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD install-plugin "$plugin" -deploy || [ $retry -ge 5 ]; do
    echo "🔁 Retry installing $plugin..."
    sleep 5
    retry=$((retry + 1))
  done
done

# Fix failed plugins
java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD install-plugin $(java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD list-plugins | grep -i '\[failed\]' | cut -d ' ' -f1) -deploy || true

# Safe restart
java -jar /var/lib/jenkins/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD safe-restart

# Wait for Jenkins to restart
restart_timeout=300
restart_elapsed=0
until nc -z localhost 8080 || [ $restart_elapsed -ge $restart_timeout ]; do
  echo "⏳ Waiting for Jenkins to restart..."
  sleep 10
  restart_elapsed=$((restart_elapsed + 10))
done

# Cleanup
sudo rm -rf /tmp/*
sudo yum clean all

echo "✅ Jenkins setup completed securely!"
