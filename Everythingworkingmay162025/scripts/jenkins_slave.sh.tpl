#!/bin/bash
set -xe

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl not found, installing..."
    sudo yum install -y curl || { echo "Failed to install curl, exiting."; exit 1; }
else
    echo "curl is already installed."
fi

# Install dependencies
sudo yum install -y wget unzip jq

# Install Java
if sudo yum install -y java-21-amazon-corretto; then
  echo "Amazon Corretto 17 installed."
else
  echo "Trying OpenJDK 11..."
  if sudo yum install -y java-11-openjdk; then
    echo "OpenJDK 11 installed."
  else
    sudo yum install -y java-1.8.0-openjdk-devel || { echo "Java install failed."; exit 1; }
  fi
fi

# Remount /tmp if using tmpfs
if mount | grep -qE '/tmp type tmpfs'; then
  echo "Replacing tmpfs /tmp..."
  sudo mkdir -p /var/tmp_disk
  sudo chmod 1777 /var/tmp_disk
  sudo mount --bind /var/tmp_disk /tmp
  echo "/tmp is now backed by disk."
else
  echo "/tmp is fine. No change."
fi

# Jenkins config variables
JENKINS_URL="${jenkins_url}"
SLAVE_NAME="${slave_name}"
WORKDIR="/home/ec2-user/jenkins-agent"
MAX_RETRIES=60

# Fetch password from SSM
echo "Fetching Jenkins admin password from SSM..."
JENKINS_PASS=$(aws ssm get-parameter --name "/jenkins/admin_password" --with-decryption --query "Parameter.Value" --output text)
JENKINS_USER="admin"

# Wait for Jenkins master to be available
count=0
until curl -sL "$JENKINS_URL/login" > /dev/null; do
  echo "Waiting for Jenkins to be ready..."
  sleep 10
  count=$((count+1))
  [ "$count" -ge "$MAX_RETRIES" ] && echo "Jenkins not ready after $MAX_RETRIES attempts." && exit 1
done

# Wait for the slave node to be defined in Jenkins
count=0
until curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/computer/$SLAVE_NAME/api/json" | grep -q "\"displayName\":\"$SLAVE_NAME\""; do
  echo "Waiting for $SLAVE_NAME to be registered in Jenkins..."
  sleep 10
  count=$((count+1))
  [ "$count" -ge "$MAX_RETRIES" ] && echo "$SLAVE_NAME not found in Jenkins after $MAX_RETRIES tries." && exit 1
done

# Setup working directory
mkdir -p "$WORKDIR/remoting"
chown -R ec2-user:ec2-user "$WORKDIR"
chmod -R 755 "$WORKDIR"
cd /home/ec2-user

# Download agent JAR
wget -q "$JENKINS_URL/jnlpJars/agent.jar" -O agent.jar
[ ! -f agent.jar ] && echo "agent.jar download failed." && exit 1
chmod 755 agent.jar

# Extract secret
SECRET=$(curl -sL -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/computer/$SLAVE_NAME/slave-agent.jnlp" | grep -oP '(?<=<argument>)[^<]+' | head -n 1)

# Prepare log file
LOG_FILE="/var/log/jenkins-agent.log"
sudo touch "$LOG_FILE"
sudo chown ec2-user:ec2-user "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Start agent
nohup java -jar agent.jar -url "$JENKINS_URL" -name "$SLAVE_NAME" -secret "$SECRET" -workDir "$WORKDIR" > "$LOG_FILE" 2>&1 &

# Wait until online
echo "Waiting for agent '$SLAVE_NAME' to come online..."
retries=0
while true; do
  ONLINE=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/computer/$SLAVE_NAME/api/json" | jq -r '.offline' 2>/dev/null)
  if [[ "$ONLINE" == "false" ]]; then
    echo "✅ Agent '$SLAVE_NAME' is online!"
    break
  fi
  sleep 5
  retries=$((retries + 1))
  if [[ $retries -ge $MAX_RETRIES ]]; then
    echo "❌ Agent '$SLAVE_NAME' failed to come online."
    exit 1
  fi
done
