#!/bin/bash
# redborder initial configuracion script for local S3

echo "INFO: Executing rb_configure_initial_s3"

#Get CDOMAIN
if [ -f /etc/redborder/cdomain ]; then
  cdomain=$(cat /etc/redborder/cdomain)
else
  echo "ERROR: cdomain not defined. Plese run rb_setup_wizard first"
  exit 1
fi

S3_IP=$(serf members -tag s3=inprogress | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
grep -q s3.${cdomain} /etc/hosts
[ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  s3.${cdomain}" >> /etc/hosts
#grep -q rbookshelf.s3.service.${cdomain} /etc/hosts
#[ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  rbookshelf.s3.service.${cdomain}" >> /etc/hosts
grep -q redborder.s3.${cdomain} /etc/hosts
[ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  redborder.s3.${cdomain}" >> /etc/hosts

# Configure Riak using chef-solo
echo "INFO: Executing riak cookbook (1)"
chef-solo -c /var/chef/cookbooks/riak/solo/riak_solo.rb -j /var/chef/cookbooks/riak/solo/riak_solo1.json
echo "INFO: Executing riak cookbook (2)"
chef-solo -c /var/chef/cookbooks/riak/solo/riak_solo.rb -j /var/chef/cookbooks/riak/solo/riak_solo1.json
echo "INFO: Executing riak cookbook (3)"
chef-solo -c /var/chef/cookbooks/riak/solo/riak_solo.rb -j /var/chef/cookbooks/riak/solo/riak_solo2.json

# Get S3 keys
if [ -f /etc/redborder/s3user.json ]; then
  access_key=$(cat /etc/redborder/s3user.json | jq .key_id -r)
  secret_key=$(cat /etc/redborder/s3user.json | jq .key_secret -r)
  if [ "x$access_key" == "x" -o "x$secret_key" == "x" ]; then
    echo "ERROR: S3 keys not created yet. Check /etc/redborder/s3user.json"
    exit 1
  fi
else
  echo "ERROR: S3 keys not created yet. File s3user.json is not present"
  exit 1
fi

# Create s3 YML config file
cat > /etc/redborder/s3_init_conf.yml <<-_RBEOF_
s3:
  access_key: $access_key
  secret_key: $secret_key
  bucket: redborder
  endpoint: s3.$cdomain
_RBEOF_

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

echo "INFO: Wait until tag s3 is ready"
serf tags -set s3=ready
while [ "x$?" != "x0" ]; do
  sleep 2
  serf tags -set s3=ready
done
