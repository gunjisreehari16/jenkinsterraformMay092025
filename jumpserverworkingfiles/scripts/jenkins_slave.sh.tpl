#!/bin/bash
set -xe

# Prereqs
sudo apt update -y
sudo apt install -y openjdk-21-jre curl wget unzip jq

# Jenkins connection config
JENKINS_URL="${jenkins_url}"
SLAVE_NAME="${slave_name}"   # Passed from Terraform
JENKINS_USER="admin"
JENKINS_PASS="admin"
WORKDIR="/home/ubuntu/jenkins-agent"
MAX_RETRIES=30

# Wait for Jenkins master to be ready
count=0
until curl -sL "$JENKINS_URL/login" > /dev/null; do
  echo "Waiting for Jenkins to be ready..."
  sleep 10
  count=$((count+1))
  [ "$count" -ge "$MAX_RETRIES" ] && echo "Jenkins not ready after $MAX_RETRIES tries." && exit 1
done

# Wait for this specific slave to be defined in Jenkins
count=0
until curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
    "$JENKINS_URL/computer/$SLAVE_NAME/api/json" \
    | grep -q "\"displayName\":\"$SLAVE_NAME\""; do
  echo "Waiting for $SLAVE_NAME to appear in Jenkins..."
  sleep 10
  count=$((count+1))
  [ "$count" -ge "$MAX_RETRIES" ] && echo "$SLAVE_NAME not registered in Jenkins after $MAX_RETRIES tries." && exit 1
done

# Prepare work directory
mkdir -p "$WORKDIR/remoting"
chown -R ubuntu:ubuntu "$WORKDIR"
chmod -R 755 "$WORKDIR"
cd /home/ubuntu

# Download Jenkins agent JAR
wget -q "$JENKINS_URL/jnlpJars/agent.jar" -O agent.jar
[ ! -f agent.jar ] && echo "agent.jar download failed." && exit 1
chmod 755 agent.jar

# Extract the secret from JNLP XML
SECRET=$(curl -sL -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/computer/$SLAVE_NAME/slave-agent.jnlp" \
  | grep -oP '(?<=<argument>)[^<]+' | head -n 1)

# Start the Jenkins agent using new style args
LOG_FILE="/var/log/jenkins-agent.log"
sudo touch "$LOG_FILE"
sudo chown ubuntu:ubuntu "$LOG_FILE"
chmod 644 "$LOG_FILE"

nohup java -jar agent.jar \
  -url "$JENKINS_URL" \
  -name "$SLAVE_NAME" \
  -secret "$SECRET" \
  -workDir "$WORKDIR" \
  > "$LOG_FILE" 2>&1 &

# Wait for agent to report as online in Jenkins
echo "🔄 Waiting for $SLAVE_NAME to come online in Jenkins..."
retries=0
while true; do
  ONLINE=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/computer/$SLAVE_NAME/api/json" | jq -r '.offline' 2>/dev/null)
  if [[ "$ONLINE" == "false" ]]; then
    echo "✅ Jenkins agent '$SLAVE_NAME' is ONLINE and connected!"
    break
  fi
  sleep 5
  retries=$((retries + 1))
  if [[ $retries -ge $MAX_RETRIES ]]; then
    echo "❌ Agent '$SLAVE_NAME' did not come online in time."
    exit 1
  fi
done
