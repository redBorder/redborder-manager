#!/bin/bash

BUCKET="bucket"
S3HOST="s3.service"
#ENDPOINT="https://$S3HOST"

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

# Generating random key and secret for minio.. 
MINIO_ACCESS_KEY="`< /dev/urandom tr -dc A-Za-z0-9 | head -c20 | sed 's/ //g'`"
MINIO_SECRET_KEY="`< /dev/urandom tr -dc A-Za-z0-9 | head -c40 | sed 's/ //g'`"

#Configure Environment Variables for minio in /etc/default/minio (used by systemd unit minio.service)
cat > /etc/default/minio <<-_RBEOF_
MINIO_OPTS="--address :9000 --console-address :9001 --config-dir /etc/minio"
MINIO_VOLUMES=/var/minio/data
MINIO_ROOT_USER=$MINIO_ACCESS_KEY
MINIO_ROOT_PASSWORD=$MINIO_SECRET_KEY
_RBEOF_

#Accept chef-client license
chef-client --chef-license accept &>/dev/null

#Configure s3 service using chef-solo
echo "INFO: Configure Minio service using chef-solo"
chef-solo -c /var/chef/solo/s3-solo.rb -j /var/chef/solo/s3-attributes.json
if [ $? -ne 0 ] ; then
  echo "ERROR: chef-solo exited with code $?"
  exit 1
fi

# Checking minio config
echo "Waiting for directory /var/minio/data/.minio.sys/config/config.json/ ..."
count=0
flag=0
while [ $count -lt 30 ] ; do
  [ -d /var/minio/data/.minio.sys/config/config.json ] && flag=1 && break
  let count=count+1
  sleep 1
done
if [ $flag -eq 0 ] ; then
  echo "ERROR: /var/minio/data/.minio.sys/config/config.json/ not found, exiting..."
  exit 1
fi

#Obtain s3 information for leader
echo "INFO: Generate /etc/redborder/s3_init_conf.yml using Minio configuration"
MINIO_IP=$(serf members -tag s3=inprogress | tr ':' ' ' | awk '{print $2}')

if [ "x$MINIO_ACCESS_KEY" != "x" -a "x$MINIO_ACCESS_KEY" != "xnull" -a \
     "x$MINIO_SECRET_KEY" != "x" -a "x$MINIO_SECRET_KEY" != "xnull" ] ; then
  cat > /etc/redborder/s3_init_conf.yml <<-_RBEOF_
---
s3:
  access_key: $MINIO_ACCESS_KEY
  secret_key: $MINIO_SECRET_KEY
  bucket: $BUCKET
  endpoint: $S3HOST
_RBEOF_

else
  echo "ERROR: can't obtain Minio access and/or secret keys, exiting..."
  exit 1
fi

# Add s3.service name to /etc/hosts
echo "INFO: Adding $S3HOST name to /etc/hosts"
grep -q s3.service /etc/hosts
[ $? -ne 0 -a "x$MINIO_IP" != "x" ] && echo "$MINIO_IP  s3.service" >> /etc/hosts

#Create bucket
echo "INFO: Configure s3cmd to create bucket"
cat > /root/.s3cfg_initial <<-_RBEOF_
[default]
access_key = $MINIO_ACCESS_KEY
secret_key = $MINIO_SECRET_KEY
check_ssl_certificate = False
check_ssl_hostname = False
host_base = $S3HOST
host_bucket = $S3HOST
use_https = True
_RBEOF_

echo "INFO: Creating bucket ($BUCKET)"
s3cmd -c /root/.s3cfg_initial mb s3://$BUCKET
if [ $? -ne 0 ] ; then
  echo "ERROR: s3cmd failed creating bucket"
  exit 1
fi


echo "INFO: S3 service configuration finished, setting serf s3=ready tag"
serf tags -set s3=ready
