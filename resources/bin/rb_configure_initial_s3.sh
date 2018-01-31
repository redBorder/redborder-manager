#!/bin/bash

BUCKET="bucket"
S3HOST="s3.service"
ENDPOINT="https://$S3HOST"

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

#Configure s3 service using chef-solo
echo "INFO: Configure Minio service using chef-solo"
chef-solo -c /var/chef/solo/s3-solo.rb -j /var/chef/solo/s3-attributes.json

#Obtain s3 information for leader
echo "INFO: Generate /etc/redborder/s3_init_conf.yml using Minio configuration"
MINIO_ACCESS_KEY=$(cat /etc/minio/config.json | jq -r .credential.accessKey)
MINIO_SECRET_KEY=$(cat /etc/minio/config.json | jq -r .credential.secretKey)
#MINIO_IP=$(serf members -tag s3=inprogress | tr ':' ' ' | awk '{print $2}')

cat > /etc/redborder/s3_init_conf.yml <<-_RBEOF_
---
access_key: $MINIO_ACCESS_KEY
secret_key: $MINIO_SECRET_KEY
bucket: $BUCKET
endpoint: $ENDPOINT
_RBEOF_

#Create bucket
echo "Configure s3cmd to create bucket"
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
echo "Creating bucket ($BUCKET)"
s3cmd -c .s3cfg_initial mb s3://$BUCKET

echo "INFO: S3 service configuration finished, setting serf s3=ready tag"
serf tags -set s3=ready
