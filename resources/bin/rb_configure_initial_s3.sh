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
MINIO_IP=$(serf members -tag s3=inprogress | tr ':' ' ' | awk '{print $2}')

# Add s3.service name to /etc/hosts
echo "INFO: Adding $S3HOST name to /etc/hosts"
grep -qE "s3\.service(\.${cdomain})?" /etc/hosts
[ $? -ne 0 -a "x$MINIO_IP" != "x" ] && echo "$MINIO_IP  s3.service s3.service.${cdomain}" >> /etc/hosts

# Add malware.s3.service name to /etc/hosts
echo "INFO: Adding malware.$S3HOST name to /etc/hosts"
grep -qE "malware\.s3\.service(\.${cdomain})?" /etc/hosts
[ $? -ne 0 -a "x$MINIO_IP" != "x" ] && echo "$MINIO_IP  malware.s3.service malware.s3.service.${cdomain}" >> /etc/hosts

for BUCKET in "${BUCKETS[@]}"; do
  echo "INFO: Creating s3 bucket ($BUCKET)"
  s3cmd -c /root/.s3cfg_initial mb s3://$BUCKET
  if [ $? -ne 0 ] ; then
    echo "ERROR: s3cmd failed creating bucket"
    exit 1
  fi
done

# Create s3 user and policy for malware bucket
RBETC="/etc/redborder"
S3INITCONF=$(if [ -f "${RBETC}/s3_init_conf.yml" ]; then echo "${RBETC}/s3_init_conf.yml"; else echo "${RBETC}/rb_init_conf.yml"; fi)
S3_MALWARE_KEY="`grep -A 4 '^malware:' ${S3INITCONF} | grep access_key | awk '{print $2}'`"
S3_MALWARE_SECRET="`grep -A 4 '^malware:' ${S3INITCONF} | grep secret_key | awk '{print $2}'`"
MALWARE_POLICY_FILE="/tmp/malware-policy.json"

echo "INFO: Creating s3 malware user"
mcli admin user add local "$S3_MALWARE_KEY" "$S3_MALWARE_SECRET" || {
  echo "ERROR: mcli failed creating malware user"
  exit 1
}

echo "INFO: Creating s3 malware policy"
cat > "$MALWARE_POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::malware", "arn:aws:s3:::malware/*"]
    }
  ]
}
EOF

mcli admin policy create local malware-policy "$MALWARE_POLICY_FILE" || {
  echo "ERROR: Failed to create malware policy"
  exit 1
}

mcli admin policy attach local malware-policy --user ${S3_MALWARE_KEY} || {
  echo "ERROR: Failed to attach malware policy to user"
  exit 1
}

rm -f "$MALWARE_POLICY_FILE"
echo "INFO: Malware user and policy created successfully"

echo "INFO: S3 service configuration finished, setting serf s3=ready tag"
serf tags -set s3=ready