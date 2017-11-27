#!/bin/bash

CLUSTER_NAME=$1

MMS_BASE_URL_EXTERNAL=http://localhost:8080
MMS_USER=jason.mimick@mongodb.com
MMS_APIKEY=69a16f3c-9cae-4daa-b0ed-ed4de790d779
MMS_APIKEY=69a16f3c-9cae-4daa-b0ed-ed4de790d779
# Delete OpsManager group!
echo "Detecting MongoDB Ops Manager Group ID for $CLUSTER_NAME."
$( bash <<EOF
curl --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--include --request \
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

curl --user "$MMS_USER:$MMS_APIKEY" --digest \
--header "Accept: application/json" \
--include --request DELETE \
"$MMS_BASE_URL_EXTERNAL/api/public/v1.0/groups/$MMS_GROUP_ID" \

for thing in secret service statefulset persistentvolume persistentvolumeclaim; do
  kubectl get $thing | grep $CLUSTER_NAME | \
  cut -d" " -f1 | xargs kubectl delete $thing
done

#kubectl delete secret k8s-mongodb-opsmanager-$CLUSTER_NAME
#kubectl delete service mongodb-server-service-$CLUSTER_NAME
#kubectl delete statefulset mongodb-server-$CLUSTER_NAME
#kubectl delete persistentvolume $CLUSTER_NAME-data-volume-1
#kubectl delete persistentvolumeclaim \
#mongodb-persistent-storage-claim-mongodb-server-$CLUSTER_NAME-0
