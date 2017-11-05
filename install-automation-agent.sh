#!/bin/bash
# Expects $MMS_GROUP_ID and $MMS_AGENT_APIKEY

curl -OL https://cloud.mongodb.com/download/agent/automation/mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm
rpm -U mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm
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

/usr/bin/mkdir /var/run/mongodb-mms-automation
/usr/bin/chown -R mongod:mongod /var/run/mongodb-mms-automation
su -s "/bin/bash" -c "/opt/mongodb-mms-automation/bin/mongodb-mms-automation-agent \
-f /etc/mongodb-mms/automation-agent.config \
-pidfilepath /var/run/mongodb-mms-automation/mongodb-mms-automation-agent.pid >> \
/var/log/mongodb-mms-automation/automation-agent-fatal.log 2>&1 &" mongod


