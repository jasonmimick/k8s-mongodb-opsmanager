#!/bin/bash
kubectl exec -it mongodb-mms-server-$1-0 --container mongodb-mms-server $2
