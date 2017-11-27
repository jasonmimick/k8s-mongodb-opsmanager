#!/bin/bash
# $1 = name of cluster


#--------->8---------cut here---------8<---------
set -eu

trap _exit_trap EXIT
trap _err_trap ERR
_showed_traceback=f

function _exit_trap
{
  local _ec="$?"
  if [[ $_ec != 0 && "${_showed_traceback}" != t ]]; then
    traceback 1
  fi
}

function _err_trap
{
  local _ec="$?"
  local _cmd="${BASH_COMMAND:-unknown}"
  traceback 1
  _showed_traceback=t
  echo "The command ${_cmd} exited with exit code ${_ec}." 1>&2
}

function traceback
{
  # Hide the traceback() call.
  local -i start=$(( ${1:-0} + 1 ))
  local -i end=${#BASH_SOURCE[@]}
  local -i i=0
  local -i j=0

  echo "Traceback (last called is first):" 1>&2
  for ((i=${start}; i < ${end}; i++)); do
    j=$(( $i - 1 ))
    local function="${FUNCNAME[$i]}"
    local file="${BASH_SOURCE[$i]}"
    local line="${BASH_LINENO[$j]}"
    echo "     ${function}() in ${file}:${line}" 1>&2
  done
}
#--------->8---------cut here---------8<---------








echo "k8s-mongodb-opsmanager -> Cluster Provisioning"
set -e
set -x

# ######################################
#
# These environment variables should be
# injected by a container orchestration service.
#
# ######################################

MMS_BASE_URL_INTERNAL=http://10.0.2.2:8080
MMS_BASE_URL_EXTERNAL=http://localhost:8080
MMS_USER=jason.mimick@mongodb.com
#MMS_APIKEY=36e70a92-d1f8-47a8-9ef4-e640cd85fc6c
MMS_APIKEY=69a16f3c-9cae-4daa-b0ed-ed4de790d779
CLUSTER_NAME=$1
GCLOUD_DISK_SIZE=2GB
KUBECTL_DISK_SIZE=2Gi
DISK_TYPE=pd-ssd
NUMBER_OF_DISKS=3
#

echo "Cluster Name: $CLUSTER_NAME"
echo "MongoDB Ops Manager Base Url External: $MMS_BASE_URL_EXTERNAL"
echo "MongoDB Ops Manager Base Url Internal: $MMS_BASE_URL_INTERNAL"
echo "MongoDB Ops Manager User: $MMS_USER"
echo "MongoDB Ops Manager Api Key: $MMS_APIKEY"
echo "Disk Info: Number: $NUMBER_OF_DISKS, \
Type: $DISK_TYPE, Size: $GCLOUD_DISK_SIZE"


# ######################################
# Fetch list of existing groups
# ######################################

tmp_json=$(mktemp).json
$( bash <<EXISTING_GROUPS_EOF
curl --silent --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
-o $tmp_json --request \
GET "$MMS_BASE_URL_EXTERNAL/api/public/v1.0/groups"
EXISTING_GROUPS_EOF
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
    echo "Creating group: $CLUSTER_NAME"
    tmp_json=$(mktemp).json
    curl --user "$MMS_USER:$MMS_APIKEY" --digest \
    -o "$tmp_json" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    --request POST \
    "$MMS_BASE_URL_EXTERNAL/api/public/v1.0/groups" \
    --data '{ "name" : "'"$CLUSTER_NAME"'" }'
    # TODO: Need to check if error in response!
else
    echo "Found Ops Manager group: $CLUSTER_NAME"
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
GET "$MMS_BASE_URL_EXTERNAL/api/public/v1.0/groups/byName/$CLUSTER_NAME"
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

MMS_AGENT_APIKEY=$(python - <<PY_END
import json; 
f=open('$tmp_json','r');
j=json.loads(f.read());
f.close();
print j['agentApiKey'];
PY_END
)
Echo "MongoDB Ops Manager Agent Api Key \
(MMS_AGENT_APIKEY):$MMS_AGENT_APIKEY"

#MMS_AGENT_APIKEY=59fc99fa3b34b9172d1edb72d6d8dadab17e3d582bcf9c25aff03d47
#MMS_GROUP_ID=59fc84cddf9db11c157eba70

echo "Creating ssd storageclass."
kubectl apply -f minikube-ssd-storageclass.yaml
for i in $(seq 1 $NUMBER_OF_DISKS); 
do
  echo "Creating $CLUSTER_NAME-data-volume-$i."
  TEMPYAML=$(mktemp).yaml
  cp minikube-ssd-persistent-volume-CLUSTER_NAME.yaml $TEMPYAML
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
--from-literal=group-id=$MMS_GROUP_ID \
--from-literal=base-url=$MMS_BASE_URL_INTERNAL

echo "now apply the service and node yamls"

echo "Creating service \
mongodb-mms-service-$CLUSTER_NAME"
TEMPYAML=$(mktemp).yaml
echo "Configuring service for \
mongodb-mms-service-$CLUSTER_NAME."
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
sed -i -e "s@%%DISK_SIZE%%@$KUBECTL_DISK_SIZE@g" $TEMPYAML
sed -i -e "s@%%NUMBER_OF_DISKS%%@$NUMBER_OF_DISKS@g" $TEMPYAML
echo "Applying $TEMPYAML"
kubectl apply -f $TEMPYAML

echo "Provisioning complete."
echo "Check $MMS_BASE_URL_EXTERNAL and validate servers."


# Now use api to launch replica set
