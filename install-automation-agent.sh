# Expects $MMS_GROUP_ID and $MMS_AGENT_APIKEY

#TODO: Error if environment varibles not set.
#curl -OL https://cloud.mongodb.com/download/agent/automation/mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm

AGENT_URL=http://129.33.250.96:8080/download/agent/automation/
AGENT=mongodb-mms-automation-agent-manager-
AGENT_VERSION=3.2.14.2187-1.x86_64.rhel7.rpm
echo "Downloading $AGENT_URL$AGENT$AGENT_VERSION"
curl -OL "$AGENT_URL$AGENT$AGENT_VERSION"

#rpm -U mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm

echo "Installing $AGENT$AGENT_VERSION"
rpm -U $AGENT$AGENT_VERSION
echo "Updating /etc/mongodb-mms/automation-agent.config with:"
echo "mmsGroupId=${MMS_GROUP_ID}"
echo "mmsApiKey=${MMS_AGENT_APIKEY}"
echo "mmsBaseUrl=${MMS_BASE_URL}"
cat << ENDMMS >> /etc/mongodb-mms/automation-agent.config

# ############################################
# mms-k8s MongoDB Ops Manager Kubernetes StatefulSet Generator
# Automatically updated on: `date`
#
# DO NOT EDIT!
#
# See: https://github.com/jasonmimick/k8s-mongodb-opsmanager
# ############################################
mmsGroupId=${MMS_GROUP_ID}
mmsApiKey=${MMS_AGENT_APIKEY}
mmsBaseUrl=${MMS_BASE_URL}
ENDMMS

chown mongod:mongod /data

echo "Creating /var/run/mongodb-mms-automation"
/usr/bin/mkdir -p /var/run/mongodb-mms-automation
/usr/bin/chown -R mongod:mongod /var/run/mongodb-mms-automation
echo "Starting automation agent..."
su -s "/bin/bash" -c "/opt/mongodb-mms-automation/bin/mongodb-mms-automation-agent \
-f /etc/mongodb-mms/automation-agent.config \
-pidfilepath /var/run/mongodb-mms-automation/mongodb-mms-automation-agent.pid >> \
/var/log/mongodb-mms-automation/automation-agent-fatal.log 2>&1 &" mongod
echo "MongoDB Ops Manager automation agent started. `date`"


