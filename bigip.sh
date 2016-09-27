#!/bin/bash

BIGIP_USER='[ADMIN-USER]'
BIGIP_PASS='[ADMIN-PASSWORD]'
BIGIP_IP='[ADMIN-IP]'
BIGIP_PORT='[ADMIN-PORT]'
BIGIP_URL_BASE="https://$BIGIP_USER:$BIGIP_PASS@$BIGIP_IP:$BIGIP_PORT"
BIGIP_TARGET_POOL="Container_pool"

DOCKER_HOST_IP=`/sbin/ifconfig eth0 |grep "inet addr" | awk '{print $2}' | cut -d: -f2`

#Check if pool exists
POOL_EXISTS=`curl -k -s -o /dev/null -w "%{http_code}" "$BIGIP_URL_BASE/mgmt/tm/ltm/pool/$BIGIP_TARGET_POOL"`
echo "$POOL_EXISTS Docker host IP = $DOCKER_HOST_IP"
if [ $POOL_EXISTS == "200" ] ; then
  echo "pool already exists"
else
  echo "Pool doesn\'t exist"
  BODY="{\"name\":\"$BIGIP_TARGET_POOL\"}"
  curl -s -k -H "Content-Type: application/json" -X POST -d $BODY $BIGIP_URL_BASE/mgmt/tm/ltm/pool
fi

#Start looping through running containers
BODY="{\"members\":["
HAS_MEMBERS=false
for CONTAINER in `/usr/bin/docker ps | awk '{print $1}' | grep -v CONTAINER`; do
  HAS_MEMBERS=true
  CONTAINER_NAT_PORT=`/usr/bin/docker inspect $CONTAINER | grep HostPort | tail -1 |cut -d: -f2 | tr -d '"'| tr -d " "`
  echo "Pool member = $DOCKER_HOST_IP:$CONTAINER_NAT_PORT"
  BODY=`echo $BODY "{\"name\":\"$DOCKER_HOST_IP:$CONTAINER_NAT_PORT\",\"address\":\"$DOCKER_HOST_IP\",\"monitor\":\"\/Common\/tcp\"}"`
done
BODY=`echo $BODY "]}"`

#TBC
#REMOTE_DOCKER_COMMAND="/sbin/ifconfig eth0 |grep \"inet addr\" | awk \'{print $2}\' | cut -d: -f2"
#REMOTE_DOCKER_IP="`ssh root@$REMOTE_DOCKER_HOST  $REMOTE_DOCKER_COMMAND`
#echo "Remote Docker IP = $REMOTE_DOCKER_IP"

for CONTAINER in `ssh root@$REMOTE_DOCKER_HOST /usr/bin/docker ps | awk '{print $1}' | grep -v CONTAINER`; do
  #echo "Remote Container - $CONTAINER"
  HAS_MEMBERS=true
  REMOTE_CONTAINER_NAT_PORT=`ssh root@$REMOTE_DOCKER_HOST /usr/bin/docker inspect $CONTAINER | grep HostPort | tail -1 |cut -d: -f2 | tr -d '"'| tr -d " "`
  echo "Remote Pool member = $REMOTE_DOCKER_HOST:$REMOTE_CONTAINER_NAT_PORT"
  BODY=`echo $BODY "{\"name\":\"$REMOTE_DOCKER_HOST:$REMOTE_CONTAINER_NAT_PORT\",\"address\":\"$REMOTE_DOCKER_HOST\",\"monitor\":\"\/Common\/tcp\"}"`
done

BODY=`echo $BODY "]}"`


if [ $HAS_MEMBERS ]; then
  curl -s -k -H "Content-Type: application/json" -X PUT -d "$BODY" $BIGIP_URL_BASE/mgmt/tm/ltm/pool/$BIGIP_TARGET_POOL
  echo "Body - $BODY"
fi
