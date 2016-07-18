#!/bin/bash

instancefile="/var/lib/cloud/data/instance-id"
ret=0

# If instacefile exists and node is not configured yet...
if [ -f $instancefile -a ! -f /etc/chef/client.pem ]; then #check
    instancename=$(cat $instancefile)

  # Take and load user-data
  if [ -f /var/lib/cloud/data/cfn-userdata ]; then
    source /var/lib/cloud/data/cfn-userdata
  elif [ -f /var/lib/cloud/instance/user-data.txt ]; then
    source /var/lib/cloud/instance/user-data.txt
  fi

  # Hostname configuration
  if [ "x$NODENAME" != "x" ]; then # Node name is defined in user-data
    newhostname=$(echo ${NODENAME} | sed 's/_//g' )
  elif [ "x$instancename" == "xiid-datasource-none"  ]; then # If instance name is not defined a random name is set (rb....)
    newhostname="rb$(< /dev/urandom tr -dc a-z0-9 | head -c10 | sed 's/ //g')"
  else # Instance name is defined but not Node name. We use instance name for node name
    newhostname=$(echo ${instancename} | sed 's/_//') # underscores are removed to avoid domain name conflicts
  fi

  # CDOMAIN configuration
  [ "x$CDOMAIN" == "x" ] && CDOMAIN="redborder.cluster"
  echo "$CDOMAIN" > /etc/redborder/cdomain

  # Change hostname
  hostnamectl set-hostname $newhostname.$cdomain

  # PUBLICDOMAIN configuration
  [ "x$PUBLICCDOMAIN" == "x" ] && PUBLICCDOMAIN="$CDOMAIN"

  # Set new hostname in network sysconfig file #Check in CentOS 7
  #grep -q "HOSTNAME=" /etc/sysconfig/network
  #if [ $? -eq 0 ]; then
  #  sed -i "s/^HOSTNAME=.*/HOSTNAME=${newhostname}.${CDOMAIN}/" /etc/sysconfig/network
  #else
  #  echo "HOSTNAME=${newhostname}.${CDOMAIN}" >> /etc/sysconfig/network
  #fi

  # To check...
  sed -i "s/ rbmanager / $newhostname /" /etc/hosts

  # Node ROLE/MODE configuration
  [ "x$NODEROLE" != "x" ] && echo "$NODEROLE" > /etc/chef/initialrole

  # check this...
  #manufacturer=$(dmidecode -t 1| grep "Manufacturer:" | sed 's/.*Manufacturer: //')
  #if [ "x$manufacturer" == "xXen" -o "x$manufacturer" == "xxen" ]; then
  #  # if the node is xen, keepalived use unicast so it should be blocked until first node is ready. completly
  #  mkdir -p /etc/redborder/lock #before /opt/rb/etc/lock
  #  if [ "x$NODEROLE" == "xcorezk" ]; then
  #    for n in keepalived rb-cloudwatch sqsld awslogs; do
  #      touch /etc/redborder/lock/$n
  #    done
  #  fi
  #fi

  # Set externals
  cat >/etc/redborder/externals.conf <<rBEOF
REGION="${REGION}"
S3TYPE="${S3TYPE}"
S3HOST="${S3HOST}"
S3BUCKET="${S3BUCKET}"
AWS_ACCESS_KEY="${AWS_ACCESS_KEY}"
AWS_SECRET_KEY="${AWS_SECRET_KEY}"
CHEF_AWS_ACCESS_KEY="${CHEF_AWS_ACCESS_KEY}"
CHEF_AWS_SECRET_KEY="${CHEF_AWS_SECRET_KEY}"
LOGWATCHG="${LOGWATCHG}"
STACKNAME="${STACKNAME}"
AUTOSCALINGGROUPNAME=${AUTOSCALINGGROUPNAME}
AUTOSCALINGGROUPID=${AUTOSCALINGGROUPID}
INSTANCE_ID=${INSTANCE_ID}
ELASTICCACHEENDPOINT="${ELASTICCACHEENDPOINT}"
ELASTICCACHECLUSTERID="${ELASTICCACHECLUSTERID}"
SQLUSER="${SQLUSER}"
SQLPASSWORD="${SQLPASSWORD}"
SQLDB="${SQLDB}"
SQLHOST="${SQLHOST}"
ENRICHMODE="${ENRICHMODE}"
NODESERVICES="${NODESERVICES}"
HOTPERIOD="${HOTPERIOD}"
MODULES="${MODULES}"
CDOMAIN="${CDOMAIN}"
PUBLICCDOMAIN="${PUBLICCDOMAIN}"
LIFECYCLEHOOKNAME="${LIFECYCLEHOOKNAME}"
SQSQUEUEURL="${SQSQUEUEURL}"
VPCID="${VPCID}"
PUBLIC_HOSTEDZONE_ID="${PUBLIC_HOSTEDZONE_ID}"
PRIVATE_HOSTEDZONE_ID="${PRIVATE_HOSTEDZONE_ID}"
MMDOWNALARMNAME="${MMDOWNALARMNAME}"
ROUTE53NAMES="${ROUTE53NAMES}"
LBINTERNAL="${LBINTERNAL}"
CRESTORE="${CRESTORE}"
CMDFINISH="${CMDFINISH}"
CMDFINISH_MASTER="${CMDFINISH_MASTER}"
rBEOF

  cat >/etc/redborder/externals.yml <<rBEOF
REGION: ${REGION}
S3TYPE: ${S3TYPE}
S3HOST: ${S3HOST}
S3BUCKET: ${S3BUCKET}
AWS_ACCESS_KEY: ${AWS_ACCESS_KEY}
AWS_SECRET_KEY: ${AWS_SECRET_KEY}
CHEF_AWS_ACCESS_KEY: ${CHEF_AWS_ACCESS_KEY}
CHEF_AWS_SECRET_KEY: ${CHEF_AWS_SECRET_KEY}
LOGWATCHG: ${LOGWATCHG}
STACKNAME: ${STACKNAME}
AUTOSCALINGGROUPNAME: ${AUTOSCALINGGROUPNAME}
AUTOSCALINGGROUPID: ${AUTOSCALINGGROUPID}
INSTANCE_ID: ${INSTANCE_ID}
ELASTICCACHEENDPOINT: ${ELASTICCACHEENDPOINT}
ELASTICCACHECLUSTERID: ${ELASTICCACHECLUSTERID}
SQLUSER: ${SQLUSER}
SQLPASSWORD: ${SQLPASSWORD}
SQLDB: ${SQLDB}
SQLHOST: ${SQLHOST}
ENRICHMODE: ${ENRICHMODE}
NODESERVICES: ${NODESERVICES}
HOTPERIOD: ${HOTPERIOD}
MODULES: ${MODULES}
CDOMAIN: ${CDOMAIN}
PUBLICCDOMAIN: ${PUBLICCDOMAIN}
LIFECYCLEHOOKNAME: ${LIFECYCLEHOOKNAME}
SQSQUEUEURL: ${SQSQUEUEURL}
VPCID: ${VPCID}
PUBLIC_HOSTEDZONE_ID: ${PUBLIC_HOSTEDZONE_ID}
PRIVATE_HOSTEDZONE_ID: ${PRIVATE_HOSTEDZONE_ID}
MMDOWNALARMNAME: ${MMDOWNALARMNAME}
ROUTE53NAMES: ${ROUTE53NAMES}
LBINTERNAL: ${LBINTERNAL}
CRESTORE: ${CRESTORE}
CMDFINISH: ${CMDFINISH}
CMDFINISH_MASTER: ${CMDFINISH_MASTER}
rBEOF

  #mkdir -p /var/chef/data/data_bag_encrypted/passwords/ # Created by RPM

  # Logwatchg password data bag
  if [ "x$LOGWATCHG" != "x" -a "x$AWS_ACCESS_KEY" != "x" -a "x$AWS_SECRET_KEY" != "x" ]; then
    mkdir -p /var/chef/data/data_bag_encrypted/passwords
    cat >/var/chef/data/data_bag_encrypted/passwords/cloudwatch.json <<rBEOF
{
"id": "cloudwatch",
"REGION": "${REGION}",
"AWS_ACCESS_KEY": "${AWS_ACCESS_KEY}",
"AWS_SECRET_KEY": "${AWS_SECRET_KEY}",
"LOGWATCHG": "${LOGWATCHG}"
}
rBEOF
  fi

  # AWS config
  cat >/etc/redborder/aws.conf <<rBEOF
[plugins]
cwlogs = cwlogs
[default]
region = ${REGION}
aws_access_key_id = ${AWS_ACCESS_KEY}
aws_secret_access_key = ${AWS_SECRET_KEY}
rBEOF

  mkdir -p /root/.aws
  cat >/root/.aws/credentials <<rBEOF
[plugins]
cwlogs = cwlogs
[default]
region = ${REGION}
aws_access_key_id = ${AWS_ACCESS_KEY}
aws_secret_access_key = ${AWS_SECRET_KEY}
rBEOF

else
  msg="Cloud instance file ($instancefile) has not been found"
  echo "$msg"
  logger -t rb_cloud_init "$msg"
  ret=1
fi

exit $ret
