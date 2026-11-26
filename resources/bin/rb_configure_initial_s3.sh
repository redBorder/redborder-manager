#!/bin/bash

# Get cdomain
[ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 $RBETC/cdomain | tr '\n' ' ' | awk '{print $1}')

BUCKETS=("bucket" "malware")
S3HOST="s3.service.${cdomain}"

echo "INFO: Executing rb_configure_initial_s3"

cat > /etc/serf/s3_query.json <<-_RBEOF_
{
    "event_handlers" : [
       "query:s3_conf=/usr/lib/redborder/bin/serf-response-file.sh /etc/redborder/s3_init_conf.yml"
    ]
}
_RBEOF_

#Mandatory to load the new handler
echo "INFO: Restarting serf. Loading new handlers"
systemctl restart serf

#Accept chef-client license
chef-client &>/dev/null

#Configure s3 service using chef-solo
echo "INFO: Configure SeaweedFS (S3) service using chef-solo"
chef-solo -c /var/chef/solo/s3-solo.rb -j /var/chef/solo/s3-attributes.json
if [ $? -ne 0 ] ; then
  echo "ERROR: chef-solo exited with code $?"
  exit 1
fi

#Obtain s3 information for leader
S3_IP=$(serf members -tag s3=inprogress | tr ':' ' ' | awk '{print $2}')

# Wait until the SeaweedFS S3 gateway answers (any HTTP code: 403 without credentials)
echo "Waiting for the S3 service in ${S3_IP}:8333 ..."
count=0
flag=0
while [ $count -lt 60 ] ; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://${S3_IP}:8333/" 2>/dev/null)
  [ "x$code" != "x000" -a "x$code" != "x" ] && flag=1 && break
  let count=count+1
  sleep 2
done
if [ $flag -eq 0 ] ; then
  echo "ERROR: the S3 service is not answering in ${S3_IP}:8333, exiting..."
  exit 1
fi

# Add s3.service name to /etc/hosts
echo "INFO: Adding $S3HOST name to /etc/hosts"
grep -qE "s3\.service(\.${cdomain})?" /etc/hosts
[ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  s3.service s3.service.${cdomain}" >> /etc/hosts

# Add malware.s3.service name to /etc/hosts
echo "INFO: Adding malware.$S3HOST name to /etc/hosts"
grep -qE "malware\.s3\.service(\.${cdomain})?" /etc/hosts
[ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  malware.s3.service malware.s3.service.${cdomain}" >> /etc/hosts

for BUCKET in "${BUCKETS[@]}"; do
  echo "INFO: Creating s3 bucket ($BUCKET)"
  s3cmd -c /root/.s3cfg_initial mb s3://$BUCKET
  if [ $? -ne 0 ] ; then
    echo "ERROR: s3cmd failed creating bucket"
    exit 1
  fi
done

echo "INFO: S3 service configuration finished, setting serf s3=ready tag"
serf tags -set s3=ready