#!/bin/bash

# User automation to deploy a replica set
# to a number of nodes given a base 
# machine name with the Ops Manager API

# ######################################
#
# These environment variables should be
# injected by a container orchestration service.
#
# ######################################

#MMS_BASE_URL=http://129.33.250.96:8080
MMS_BASE_URL=http://localhost:8080
MMS_USER=jason.mimick@mongodb.com
#MMS_APIKEY=36e70a92-d1f8-47a8-9ef4-e640cd85fc6c
MMS_APIKEY=69a16f3c-9cae-4daa-b0ed-ed4de790d779
CLUSTER_NAME=$1
GCLOUD_DISK_SIZE=30GB
KUBECTL_DISK_SIZE=30Gi
DISK_TYPE=pd-ssd
NUMBER_OF_DISKS=3
MONGODB_VERSION=3.4.10

function debug() { ((DEBUG_LOG)) && echo "### $*"; }

# template config just has 3 nodes, need to fix that:

# Fetch agent apikey and groupid
echo "Detecting MongoDB Ops Manager Group ID and \
Agent Api Key for $CLUSTER_NAME."
tmp_json=$(mktemp).json
$( bash <<EOF
curl --silent --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
-o $tmp_json --request \
GET "$MMS_BASE_URL/api/public/v1.0/groups/byName/$CLUSTER_NAME"
EOF
) 

MMS_GROUP_ID=$(python - <<PY_END
import json; 
f=open('$tmp_json','r');
j=json.loads(f.read());
f.close();
print j['id'];
PY_END
)
Echo "MongoDB Ops Manager Group Id (MMS_GROUP_ID):$MMS_GROUP_ID"

#GET /api/public/v1.0/groups/GROUP-ID/automationConfig
# Fetch automationConfig
echo "Getting Automation Config for Group ID: $MMS_GROUP_ID"
tmp_json=$(mktemp).json
$( bash <<EOF
curl --silent --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
-o $tmp_json --request \
GET "$MMS_BASE_URL/api/public/v1.0/groups/$MMS_GROUP_ID/automationConfig"
EOF
) 

AUTO_CONFIG_URL=$tmp_json
#AUTO_CONFIG_URL=./automationConfigReplicaSetTemplate.json


debug "Reading automation agent config from $AUTO_CONFIG_URL"

#debug "Adding MongoDB Version $MONGODB_VERSION \
#to automation config."
#AUTO_CONFIG=$(jq --arg MONGODB_VERSION "$MONGODB_VERSION" \
#'.mongoDbVersions[0].name = $MONGODB_VERSION' \
#$AUTO_CONFIG_URL)
num_disks_less_one="$(($NUMBER_OF_DISKS-1))"
# update first member & stick in variable,
# then iterate over number needed, update and
# push onto processes array
MDB_PORT=30036
AUTO_CONFIG=$(jq --arg MDB_PORT "$MDB_PORT" \
--arg MONGODB_VERSION "$MONGODB_VERSION" \
'.processes[0].processType = "mongod" | .processes[0].authSchemaVersion = 5 | .processes[0].featureCompatibilityVersion = "3.4" | .processes[0].version = $MONGODB_VERSION | .processes[0].args2_6.net.port = $MDB_PORT' $AUTO_CONFIG_URL)

CONTAINER=mongodb-server-$CLUSTER_NAME-0
hostname=$(kubectl exec -it $CONTAINER \
--container mongodb-server -- hostname -f | tr -d '\r')
hostname=$(echo -n $hostname)
debug "hostname=$hostname"
AUTO_CONFIG=$(echo $AUTO_CONFIG | \
jq --arg hostname "$hostname" \
'.processes[0].hostname = $hostname')

debug $AUTO_CONFIG
nodename="$CLUSTER_NAME-db_0"
dbPath="/data/$nodename"
logFile="/data/$nodename/mongodb.log"
debug $AUTO_CONFIG | jq '.processes[0].args2_6.storage.dbPath'
AUTO_CONFIG=$(echo $AUTO_CONFIG | \
jq --arg dbPath "$dbPath" \
--arg nodename "$nodename" \
--arg CLUSTER_NAME "$CLUSTER_NAME" \
--arg logFile "$logFile" \
'.processes[0].processType = "mongod" | .processes[0].args2_6.storage.dbPath = $dbPath | .processes[0].args2_6.replication.replSetName = $CLUSTER_NAME | .processes[0].args2_6.systemLog.path = $logFile | .processes[0].name = $nodename | .replicaSets[0]._id = $CLUSTER_NAME | .replicaSets[0].members[0].host= $nodename | .replicaSets[0].members[0]._id = 0')


for i in $(seq 1 $num_disks_less_one); 
do
  debug "Appending $CLUSTER_NAME-mongodb-$i to automation config."
  nodename="$CLUSTER_NAME-db_$i"
  dbPath="/data/$nodename"
  logFile="/data/$nodename/mongodb.log"
  debug $AUTO_CONFIG | jq '.processes[0].args2_6.storage.dbPath'
  AUTO_CONFIG=$(echo $AUTO_CONFIG | \
  jq '.processes[.processes | length] = .processes[0]')
  AUTO_CONFIG=$(echo $AUTO_CONFIG | \
  jq '.replicaSets[0].members[.replicaSets[0].members | length] = .replicaSets[0].members[0]')
  CONTAINER=mongodb-server-$CLUSTER_NAME-$i
  hostname=$(kubectl exec -it $CONTAINER \
  --container mongodb-server -- hostname -f | tr -d '\r')
  hostname=$(echo -n $hostname)
  debug "CONTAINER=$CONTAINER\nhostname=$hostname"
  AUTO_CONFIG=$(echo $AUTO_CONFIG | \
  jq --arg dbPath "$dbPath" \
  --arg i "$i" \
  --arg hostname "$hostname" \
  --arg nodename "$nodename" \
  --arg CLUSTER_NAME "$CLUSTER_NAME" \
  --arg logFile "$logFile" \
  '.processes[($i | tonumber)].hostname = $hostname | .processes[($i | tonumber)].args2_6.storage.dbPath = $dbPath | .processes[($i | tonumber)].args2_6.replication.replSetName = $CLUSTER_NAME | .processes[($i | tonumber)].args2_6.systemLog.path = $logFile | .processes[($i | tonumber)].name = $nodename | .replicaSets[0].members[($i | tonumber)].host = $nodename | .replicaSets[0].members[($i | tonumber)]._id = ($i | tonumber)')
  
done
#echo $AUTO_CONFIG

# POST the config!@

tmp_json=$(mktemp).json
tmp_json_output=$(mktemp).json
echo $AUTO_CONFIG > $tmp_json
curl -vvv -i --user "$MMS_USER:$MMS_APIKEY" --digest \
-o "$tmp_json_output" \
--header "Content-Type: application/json" \
--request PUT \
"$MMS_BASE_URL/api/public/v1.0/groups/$MMS_GROUP_ID/automationConfig" \
-d @$tmp_json
debug "PUTting updated automation config from $tmp_json"
debug "Response saved here: $tmp_json_output"
cat $tmp_json_output
