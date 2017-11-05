#!/bin/bash
# $1 = name of cluster

echo "k8s-mongodb-opsmanager -> Cluster Provisioning"
set -e
set -x

# ######################################
#
# These environment variables should be
# injected by a container orchestration service.
#
# ######################################

MMS_BASE_URL=http://129.33.250.96:8080
MMS_USER=jason.mimick@mongodb.com
MMS_APIKEY=36e70a92-d1f8-47a8-9ef4-e640cd85fc6c
CLUSTER_NAME=$1
DISK_SIZE=30GB
DISK_TYPE=pd-ssd
NUMBER_OF_DISKS=3
#

echo "Cluster Name: $CLUSTER_NAME"
echo "MongoDB Ops Manager Base Url: $MMS_BASE_URL"
echo "MongoDB Ops Manager User: $MMS_USER"
echo "MongoDB Ops Manager Api Key: $MMS_APIKEY"
echo "Disk Info: Number: $NUMBER_OF_DISKS, \
Type: $DISK_TYPE, Size: $DISK_SIZE"


GOT_CLUSTER=`gcloud container clusters list \
--filter="name:$CLUSTER_NAME"`
if [[ $GOT_CLUSTER ]]; then
  gcloud container clusters delete "$CLUSTER_NAME" --quiet
fi
gcloud container clusters create "$CLUSTER_NAME"
for i in $(seq 1 $NUMBER_OF_DISKS); 
do
  # TODO - If we deleted the cluster, then delete the disks
  DISK_NAME="$CLUSTER_NAME"-disk-$i
  GOT_DISK=$( bash <<EOF
  gcloud compute disks list --uri | rev | \
  cut -d "/" -f 1 | rev | grep $DISK_NAME
  )
  EOF
  
  if [[ $GOT_DISK ]]; then
    echo "Disk '$DISK_NAME' existed so deleting."
    gcloud compute disks delete "$CLUSTER_NAME"-disk-$i --quiet
  fi
  echo "Creating disk $DISK_NAME."
  gcloud compute disks create --size $DISK_SIZE \
--type $DISK_TYPE $DISK_NAME
done

# ######################################
# Fetch list of existing groups
# ######################################

tmp_json=$(mktemp).json
$( bash <<EOF
curl --silent --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
-o $tmp_json --request \
GET "$MMS_BASE_URL/api/public/v1.0/groups"
EOF
)

EXISTING_GROUPS=$(python - <<PY_END 
import json; 
f=open('$tmp_json','r');
j=json.loads(f.read())['results'];
f.close();
print ','.join(map((lambda x: x['name']),j));
PY_END
)
echo "Found existing MongoDB Ops Manager \
groups: $EXISTING_GROUPS"

# If a group called $CLUSTER_NAME does not 
# already exist, then create it.

IFS=',' read -r -a groups <<< "$EXISTING_GROUPS"

if [[ ! " ${groups[@]} " =~ " ${CLUSTER_NAME} " ]]; then
    # Need to create the group
    echo "No Ops Manager group called '$CLUSTER_NAME' found."
    echo "Creating group: $CLUSER_NAME"
    tmp_json=$(mktemp).json
    curl --user "$MMS_USER:$MMS_APIKEY" --digest \
    -o "$tmp_json"
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    --request POST \
    "$MMS_BASE_URL/api/public/v1.0/groups" \
    --data '{ "name" : "$CLUSTER_NAME" }'
else
    echo "Found Ops Manager group: $CLUSER_NAME"
fi


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
j=json.loads(f.read())['results'];
f.close()
print j['id'];
PY_END
)
Echo "MongoDB Ops Manager Group Id (MMS_GROUP_ID):$MMS_GROUP_ID"

MMS_AGENT_APIKEY=$(python - <<PY_END 
import json; 
f=open('$tmp_json','r');
j=json.loads(f.read())['results'];
f.close()
print j['agentApiKey'];
PY_END
)
Echo "MongoDB Ops Manager Agent Api Key \
(MMS_AGENT_APIKEY):$MMS_AGENT_APIKEY"

#MMS_AGENT_APIKEY=59fc99fa3b34b9172d1edb72d6d8dadab17e3d582bcf9c25aff03d47
#MMS_GROUP_ID=59fc84cddf9db11c157eba70

echo "Creating ssd storageclass."
kubectl apply -f gce-ssd-storageclass.yaml
for i in $(seq 1 $NUMBER_OF_DISKS); 
do
  echo "Creating $CLUSTER_NAME-data-volume-$i."
  TEMPYAML=$(mktemp).yaml
  cp gcd-ssd-persistentvolume.yaml $TEMPYAML
  sed -i -e "s@%%CLUSTER_NAME%%@$CLUSTER_NAME@g"  $TEMPYAML
  sed -i -e "s@%%NUM%%@$i@g" $TEMPYAML
  echo "Applying $TEMPYAML"
  cat $TEMPYAML
  kubectl apply -f $TEMPYAML
#  rm $TEMPYAML
  echo "Created $CLUSTER_NAME-data-volume-$i."
done

echo "Creating secret k8s-mongodb-opsmanager-$CLUSTER_NAME"
echo "Keys: group-id,agent-apikey"
kubectl create secret generic k8s-mongodb-opsmanager-$CLUSTER_NAME \
--from-literal=agent-apikey=$MMS_AGENT_APIKEY \
--from-literal=group-id=$MMS_GROUP_ID

echo "now apply the service and node yamls"

echo "Creating service \
mongodb-mms-server-service-$CLUSTER_NAME"
TEMPYAML=$(mktemp).yaml
echo "Configuring service for \
mongodb-mms-server-service-$CLUSTER_NAME."
echo "Using $TEMPYAML."
cp mongodb-mms-service-CLUSTER_NAME.yaml $TEMPYAML
sed -i -e "s@%%CLUSTER_NAME%%@$CLUSTER_NAME@g"  $TEMPYAML
echo "Applying $TEMPYAML"
kubectl apply -f $TEMPYAML




TEMPYAML=$(mktemp).yaml
echo "Configuring stateful set for $CLUSTER_NAME"
echo "Using $TEMPYAML."
cp mongodb-mms-server-CLUSTER_NAME.yaml $TEMPYAML
sed -i -e "s@%%CLUSTER_NAME%%@$CLUSTER_NAME@g"  $TEMPYAML
sed -i -e "s@%%DISK_SIZE%%@$DISK_SIZE@g" $TEMPYAML
echo "Applying $TEMPYAML"
kubectl apply -f $TEMPYAML

echo "Provisioning complete."
echo "Check $MMS_BASE_URL and validate servers."


# Now use api to launch replica set
