#!/bin/bash
# Script to execute rb_create_druid_metadata.rb script daily in cron
source /etc/profile.d/rvm.sh

service="minio"
s3_config=/root/.s3cfg_initial

if !systemctl status "$service" 2> /dev/null | grep -Fq "Active:"; then
  #if [ ! -f "/etc/init.d/$service" ]; then
  exit 1
fi

systemctl status $service > /dev/null
  if [ $? != 0 ]; then
  exit 1
fi

date=$(date -d '-1 day' '+%Y-%m-%d')
namespaces=$(/bin/s3cmd ls s3://bucket/rbdata/ --config $s3_config | cut -d "/" -f 5)
bucket="bucket"
if [ -f /etc/externals.conf ]; then
  remote_bucket=$(cat /etc/externals.conf | grep S3BUCKET | cut -d "=" -f 2)
  echo $remote_bucket
  if [ $remote_bucket != '""' ]; then
    bucket=$remote_bucket
  fi
fi

rvm gemset use web &>/dev/null
for ns in $namespaces; do
  /usr/lib/redborder/scripts/rb_create_druid_metadata.rb -d $ns -b $bucket -t $ns -u -g $date >> /var/log/daily_druid_metadata.log
done
exit 0