#!/bin/bash
# Expects $MMS_GROUP_ID and $MMS_AGENT_APIKEY

curl -OL https://cloud.mongodb.com/download/agent/automation/mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm
sudo rpm -U mongodb-mms-automation-agent-manager-4.5.1.2319-1.x86_64.rhel7.rpm
sudo tee -a /etc/mongodb-mms-automation-agent.config > /dev/null <<ENDMMS
# mms-k8s MongoDB Ops Manager Kubernetes StatefulSet Generator
# Generated on: `date`
mmsGroupId=$MMS_GROUP_ID
mmsApiKey=$MMS_AGENT_APIKEY"
ENDMMS"
sudo mkdir -p /data"
sudo chown mongod:mongod /data"

