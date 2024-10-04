#!/bin/bash
# redborder LEADER node initialization
# This node is the first of the cluster. It install and configure chef-server

source /etc/profile
source $RBLIB/rb_manager_functions.sh
source $RBETC/rb_init_conf.conf

function configure_db(){
  # Configuring database passwords
  [ "x$REDBORDERDBPASS" == "x" ] && REDBORDERDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  [ "x$DRUIDDBPASS" == "x" ] && DRUIDDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  [ "x$RADIUSPASS" == "x" ] && RADIUSPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  [ "x$MONITORSPASS" == "x" ] && MONITORSPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"

  # Druid DATABASE
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE USER druid WITH PASSWORD '$DRUIDDBPASS';"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "DROP DATABASE IF EXISTS druid;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "GRANT druid TO $DB_ADMINUSER;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE DATABASE druid OWNER druid;"

  # redborder DATABASE
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE USER redborder WITH PASSWORD '$REDBORDERDBPASS';"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "DROP DATABASE IF EXISTS redborder;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "GRANT redborder TO $DB_ADMINUSER;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE DATABASE redborder OWNER redborder;"

  # radius DATABASE
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE USER radius WITH PASSWORD '$RADIUSPASS';"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "DROP DATABASE IF EXISTS radius;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "GRANT radius TO $DB_ADMINUSER;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE DATABASE radius OWNER radius;"

  # monitors DATABASE
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE USER monitors WITH PASSWORD '$MONITORSPASS';"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "DROP DATABASE IF EXISTS monitors;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "GRANT monitors TO $DB_ADMINUSER;"
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE DATABASE monitors OWNER monitors;"

  # Replication User
  env PGPASSWORD=$DB_ADMINPASS psql -U $DB_ADMINUSER -h $DB_HOST -c "CREATE USER rep REPLICATION LOGIN CONNECTION LIMIT 100;"

}

function configure_sensor_nodes(){
  # CEP sensor
  mkdir -p /var/chef/data/node/
  cat > /var/chef/data/node/cep.json <<- _RBEOF2_
{
  "name": "cep",
  "chef_environment": "_default",
  "run_list": [
    "role[cep-sensor]"
  ],
  "normal": {
    "ipaddress": "127.0.0.1",
    "rbname": "CEP",
    "rbversion": null,
    "redborder": {
      "ipaddress": "127.0.0.1",
      "observation_id": "",
      "parent_id": null,
      "sensor_uuid": "$(cat /proc/sys/kernel/random/uuid)"
    }
  }
}
_RBEOF2_
}

function configure_dataBags(){

  # Chef server configuration file
  ERCHEFCFG="/opt/opscode/embedded/service/opscode-erchef/sys.config"
  S3INITCONF="${RBETC}/s3_init_conf.yml"

  # Data bag encrypted key
  [ "x$DATABAGKEY" == "x" ] && DATABAGKEY="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  echo $DATABAGKEY > /etc/chef/encrypted_data_bag_secret

  # Chef middleware configurations
  OCID_DBCFG="/opt/opscode/embedded/service/oc_id/config/database.yml"
  OCBIFROST_DBCFG="/opt/opscode/embedded/service/oc_bifrost/sys.config"

  # Obtaining chef database current configuration
  OPSCODE_DBHOST="`grep {db_host $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  [ "x$OPSCODE_DBHOST" == "x127.0.0.1" ] && OPSCODE_DBHOST=$IPLEADER
  OPSCODE_DBPORT="`grep {db_port $ERCHEFCFG |sed 's/.*{db_port, //' | sed 's/},//'`"
  OPSCODE_DBPASS="`grep {db_pass $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  OPSCODE_OCID_PASS="`grep password $OCID_DBCFG | sed 's/ password: //' | tr -d ' '`"
  OPSCODE_OCBIFROST_PASS="`grep db_pass $OCBIFROST_DBCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//' | sed 's/" },//'`"

  # Obtaining chef cookbook storage current configuration
  S3KEY="`grep access_key ${S3INITCONF} | awk '{print $2}'`"
  S3SECRET="`grep secret_key ${S3INITCONF} | awk '{print $2}'`"
  S3HOST="`cat /etc/redborder/rb_init_conf.yml | grep endpoint | awk {'print $2'}`" #CHECK If bookshelf enabled, this value will be empty
  S3URL="`grep s3_url, $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  S3EXTERNALURL="`grep s3_external_url $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`" #CHECK when {s3_external_url, host_header},
  S3BUCKET="`grep s3_platform_bucket_name $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"

  # IF S3HOST not found, set default: s3.service
  [ "x$S3HOST" = "x" ] && S3HOST="s3.service"

  # Vault data bag configuration
  HASH_KEY="yourenterprisekey"
  HASH_FUNCTION="SHA256"

  ## Data bags ##
  mkdir -p /var/chef/data/data_bag/passwords/
  mkdir -p /var/chef/data/data_bag/rBglobal/
  mkdir -p /var/chef/data/data_bag/certs/
  mkdir -p /var/chef/data/data_bag/backend/

  ## DB opscode (chef) passwords
  cat > /var/chef/data/data_bag/passwords/db_opscode_chef.json <<-_RBEOF_
{
  "id": "db_opscode_chef",
  "username": "opscode_chef",
  "database": "opscode_chef",
  "hostname": "$OPSCODE_DBHOST",
  "port": "$OPSCODE_DBPORT",
  "pass": "$OPSCODE_DBPASS",
  "ocid_pass": "$OPSCODE_OCID_PASS",
  "ocbifrost_pass": "$OPSCODE_OCBIFROST_PASS"
}
_RBEOF_
  # monitors rBglobal
  cat > /var/chef/data/data_bag/rBglobal/monitors.json <<-_RBEOF_
{
  "id": "monitors",
  "description": "available monitors"
}

_RBEOF_

  # S3 passwords
  cat > /var/chef/data/data_bag/passwords/s3.json <<-_RBEOF_
{
  "id": "s3",
  "s3_access_key_id": "$S3KEY",
  "s3_secret_key_id": "$S3SECRET",
  "s3_host": "$S3HOST",
  "s3_url": "$S3URL",
  "s3_external_url": "$S3EXTERNALURL",
  "s3_bucket": "$S3BUCKET"
}
_RBEOF_

  # DB druid passwords
  cat > /var/chef/data/data_bag/passwords/db_druid.json <<-_RBEOF_
{
  "id": "db_druid",
  "username": "druid",
  "database": "druid",
  "hostname": "$OPSCODE_DBHOST",
  "port": "$OPSCODE_DBPORT",
  "pass": "$DRUIDDBPASS"
}
_RBEOF_

  # DB redborder passwords
  cat > /var/chef/data/data_bag/passwords/db_redborder.json <<-_RBEOF_
{
  "id": "db_redborder",
  "username": "redborder",
  "database": "redborder",
  "hostname": "$OPSCODE_DBHOST",
  "port": "$OPSCODE_DBPORT",
  "pass": "$REDBORDERDBPASS"
}
_RBEOF_

  # DB radius passwords
  cat > /var/chef/data/data_bag/passwords/db_radius.json <<- _RBEOF2_
{
  "id": "db_radius",
  "username": "radius",
  "database": "radius",
  "hostname": "$OPSCODE_DBHOST",
  "port": "$OPSCODE_DBPORT",
  "pass": "$RADIUSPASS"
}
_RBEOF2_

  # Vault passwords
  cat > /var/chef/data/data_bag/passwords/vault.json <<-_RBEOF_
{
  "id": "vault",
  "hash_key": "$HASH_KEY",
  "hash_function": "$HASH_FUNCTION"
}
_RBEOF_

  # Elasticache configuration
  cat > /var/chef/data/data_bag/rBglobal/elasticache.json <<-_RBEOF_
{
  "id": "elasticache",
  "cfg_address": "$ELASTICACHE_ADDRESS",
  "cfg_port": $ELASTICACHE_PORT
}
_RBEOF_

  # Licenses configuration
  cat > /var/chef/data/data_bag/rBglobal/licenses.json <<-_RBEOF_
{
  "id": "licenses",
  "licenses": {},
  "sensors": {}
}
_RBEOF_

  # External services
  MODE_PG="external"
  MODE_S3="external"
  [ -f /etc/redborder/postgresql_init_conf.yml ] && MODE_PG="onpremise"
  [ -f /etc/redborder/s3_init_conf.yml ] && MODE_S3="onpremise"
  cat > /var/chef/data/data_bag/rBglobal/external_services.json <<-_RBEOF_
{
  "id": "external_services",
  "postgresql": "$MODE_PG",
  "s3": "$MODE_S3"
}
_RBEOF_

  #webui secret token
  WEBISECRET="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  cat > /var/chef/data/data_bag/passwords/webui_secret.json <<-_RBEOF_
{
  "id": "webui_secret",
  "secret": "$WEBISECRET"
}
_RBEOF_

  #kafka topics #TODO
  cat > /var/chef/data/data_bag/backend/kafka_topics.json <<-_RBEOF_
{
  "id": "kafka_topics",
  "topics": {
    "rb_flow": {
      "partitions": 1,
      "replication_factor": 1,
      "log_compaction": false
    },
    "rb_event": {
      "partitions": 1,
      "replication_factor": 1,
      "log_compaction": false
    }
  }
}
_RBEOF_

  ## Domain
  cat > /var/chef/data/data_bag/rBglobal/domain.json <<-_RBEOF_
{
  "id": "domain",
  "name": "${cdomain}"
}
_RBEOF_

  ## Public domain
  [ "x$PUBLICCDOMAIN" == "x" ] && PUBLICCDOMAIN="$cdomain"
  cat > /var/chef/data/data_bag/rBglobal/publicdomain.json <<-_RBEOF_
{
  "id": "publicdomain",
  "name": "${PUBLICCDOMAIN}"
}
_RBEOF_

  ## Generating cluster uuid
  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/cluster.json <<-_RBEOF_
{
  "id": "cluster",
  "uuid": "$(cat /proc/sys/kernel/random/uuid)"
}
_RBEOF_

  ## Generating external virtual ip
  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/ipvirtual-external-webui.json <<-_RBEOF_
{
  "id": "ipvirtual-external-webui"
}
_RBEOF_

  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/ipvirtual-external-f2k.json <<-_RBEOF_
{
  "id": "ipvirtual-external-f2k"
}
_RBEOF_

  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/ipvirtual-external-sfacctd.json <<-_RBEOF_
{
  "id": "ipvirtual-external-sfacctd"
}
_RBEOF_

  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/ipvirtual-external-kafka.json <<-_RBEOF_
{
  "id": "ipvirtual-external-kafka"
}
_RBEOF_

  mkdir -p /var/chef/data/data_bag/rBglobal
  cat > /var/chef/data/data_bag/rBglobal/ipvirtual-internal-postgresql.json <<-_RBEOF_
{
  "id": "ipvirtual-internal-postgresql"
}
_RBEOF_


LICMODE=$(head -n 1 /etc/licmode 2>/dev/null)
  if [ "x$LICMODE" != "xglobal" -a "x$LICMODE" != "xorganization" ]; then
    LICMODE="global"
    echo -n $LICMODE > /etc/licmode
  fi
  
  mkdir -p /var/chef/data/data_bag_encrypted/rBglobal/
  cat > /var/chef/data/data_bag_encrypted/rBglobal/licmode.json <<- _RBEOF2_
{
  "id": "licmode",
  "mode": "$LICMODE"
}
_RBEOF2_

  ## Initial certificate for certs data bag
  env CDOMAIN=$cdomain rb_create_nginx_certs > /var/chef/data/data_bag/certs/nginx.json

  ## Create root pem from the chef server admin.pem
  mkdir -p /var/chef/data/data_bag_encrypted/certs
  cat > /var/chef/data/data_bag_encrypted/certs/root.json <<-_RBEOF_
{
  "id": "root",
  "certname": "root",
  "private_rsa": "`cat /etc/chef/admin.pem | tr '\n' '|' | sed 's/|/\\\\n/g'`"
}
_RBEOF_
}

function create_buckets(){
  echo "create_buckets"
}

function configure_leader(){
  # Check if leader is configuring now
  if [ -f /var/lock/leader-configuring.lock ]; then
    echo "INFO: this manager is being configuring just now!"
    exit 0
  fi
  touch /var/lock/leader-configuring.lock

  # Create specific role for this node
  e_title "Creating custom chef role"
  mv /var/chef/data/role/manager_node.json /var/chef/data/role/$(hostname -s).json
  # Change hostname in new role
  sed -i "s/manager_node/$(hostname -s)/g" /var/chef/data/role/$(hostname -s).json

  # Configure databases
  e_title "Configuring DataBases"
  configure_db

  # Configure Sensors nodes
  e_title "Configuring Sensor nodes"
  configure_sensor_nodes

  # Configure DataBags
  e_title "Configuring Data bags"
  configure_dataBags

  # Upload chef data (ROLES, DATA BAGS, ENVIRONMENTS ...)
  e_title "Uploading chef data (ROLES, DATA BAGS, ENVIRONMENTS ...)"
  $RBBIN/rb_upload_chef_data.sh -y

  # Delete encrypted data BAGS
  rm -rf /var/chef/data/data_bag_encrypted/*

  # COOKBOOKS
  # Save into cache directory
  e_title "Uploading cookbooks"
  mkdir -p /var/chef/cache/cookbooks/

  $RBBIN/rb_upload_cookbooks.sh

  e_title "Registering chef-client ..."
  chef-client
  # Adding chef role to node
  knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
  knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[$CLIENTNAME]"
  # Set client.pem as readable
  chmod a+r /etc/chef/client.pem

  # MANAGER MODES
  e_title "Configuring manager mode"
  # Set manager role
  [ "x$MANAGERMODE" == "x" ] && MANAGERMODE="custom"
  $RBBIN/rb_set_mode $MANAGERMODE

  # Update timestamp #??#
  $RBBIN/rb_update_timestamp &>/dev/null

  # Copy web certificates (use only chef-server certificate) #CHECK #??#
  mkdir -p /root/.chef/trusted_certs/
  rsync /var/opt/opscode/nginx/ca/*.crt /root/.chef/trusted_certs/
  mkdir -p /home/redborder/.chef/trusted_certs/
  rsync /var/opt/opscode/nginx/ca/*.crt /home/redborder/.chef/trusted_certs/
  chown -R redborder:redborder /home/redborder/.chef

  # Clean yum data (to install packages from chef)
  yum clean all

  #Add client to admins group
  knife group add client `hostname -s` admins &>/dev/null

  # Multiple runs of chef-client
  e_title "Configuring Chef-Client. Please wait...  "

  e_title "redborder install run (1/4) $(date)" | tee -a /root/.install-chef-client.log
  chef-client | tee -a /root/.install-chef-client.log


  # Replace chef-server SV init scripts by systemd scripts
  /usr/bin/chef-server-ctl graceful-kill &>/dev/null
  if [ "$(ls -A /opt/opscode/service)" ]; then
    e_title "Stopping default private-chef-server services"
    /usr/bin/chef-server-ctl stop &>/dev/null
    e_title "Starting systemd chef-server services"
    for i in `ls /opt/opscode/service/ | sed 's/opscode-//g'`;do
      systemctl enable opscode-$i &>/dev/null && systemctl start opscode-$i &>/dev/null
      rm -rf /opt/opscode/service/$i &>/dev/null
    done
  fi

  e_title "redborder install run (2/4) $(date)" | tee -a /root/.install-chef-client.log
  chef-client | tee -a /root/.install-chef-client.log
  
  e_title "redborder install run (3/4) $(date)" | tee -a /root/.install-chef-client.log
  chef-client | tee -a /root/.install-chef-client.log

  e_title "Creating database structure $(date)"
  chef-solo -c /var/chef/solo/webui-solo.rb -j /var/chef/solo/webui-attributes.json
  
  e_title "redborder install run (4/4) $(date)" | tee -a /root/.install-chef-client.log
  chef-client | tee -a /root/.install-chef-client.log
}

function set_external_service_names {
  S3_IP=$(serf members -tag s3=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
  grep -q s3.service /etc/hosts
  [ $? -ne 0 -a "x$S3_IP" != "x" ] && echo "$S3_IP  s3.service s3.service.${cdomain}" >> /etc/hosts

  PSQL_IP=$(serf members -tag postgresql=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
  grep -q master.postgresql.service /etc/hosts
  [ $? -ne 0 -a "x$PSQL_IP" != "x" ] && echo "$PSQL_IP  master.postgresql.service master.postgresql.service.${cdomain}" >> /etc/hosts
}

########
# MAIN #
########
start_script=$(date +%s) # Save init time

CHEFUSER="admin" # Chef server admin user
CHEFORG="redborder" # Chef org
CHEFPASS="redborder" # Chef pass

CLIENTNAME=`hostname -s`
IPLEADER=`serf members -status alive -name=$CLIENTNAME -format=json | jq -r .members[].addr | cut -d ":" -f 1`
MANAGERMODE=`serf members -status alive -name=$CLIENTNAME -format=json | jq -r .members[].tags.mode`

# Get cdomain
cdomain=$(head -n 1 /etc/redborder/cdomain | tr '\n' ' ' | awk '{print $1}')

############################################
# CHEF SERVER Installation & Configuration #
############################################

# Add erchef domain /etc/hosts (consul is not ready at this moment)
grep -q erchef.${cdomain} /etc/hosts
[ $? -ne 0 ] && echo "$IPLEADER  erchef.service.${cdomain}" >> /etc/hosts
set_external_service_names

# Chef server Installation
e_title "Installing Chef-Server from repository"
yum install -y redborder-chef-server

# Read S3 & Postgresql configuration
rb_init_chef

# Set chef-server.rb configuration file (S3)
[ -f /etc/redborder/chef-server-s3.rb ] && cat /etc/redborder/chef-server-s3.rb >> /etc/opscode/chef-server.rb #&& rm -f /etc/redborder/chef-server-s3.rb

# Set chef-server.rb configuration file (postgresql) and obtain database credentials
if [ -f /etc/redborder/chef-server-postgresql.rb ]; then
  cat /etc/redborder/chef-server-postgresql.rb >> /etc/opscode/chef-server.rb
  DB_ADMINUSER=$(cat /etc/redborder/chef-server-postgresql.rb | grep "db_superuser.]" | awk {'print $3'} | tr -d "\"")
  DB_ADMINPASS=$(cat /etc/redborder/chef-server-postgresql.rb | grep "db_superuser_password.]" | awk {'print $3'}| tr -d "\"")
  DB_HOST=$(cat /etc/redborder/chef-server-postgresql.rb | grep "vip.]" | awk {'print $3'}| tr -d "\"")
  #rm -f /etc/redborder/chef-server-postgresql.rb
else
  DB_ADMINUSER="opscode-pgsql"
  DB_ADMINPASS="" #TODO
  DB_HOST=$IPLEADER
fi

# Set chef-server internal nginx port to 4443
echo "nginx['ssl_port'] = 4443" >> /etc/opscode/chef-server.rb
echo "nginx['non_ssl_port'] = 4480" >> /etc/opscode/chef-server.rb

# Chef server initial configuration
e_title "Configuring Chef-Server"
/usr/bin/chef-server-ctl reconfigure --chef-license=accept | tee -a /root/.install-chef-server.log

# TODO: check if this is the way or file acls
[ -f /etc/opscode/private-chef-secrets.json ] && chown opscode. /etc/opscode/private-chef-secrets.json

# TODO: Check why we need to sleep here
echo "Sleeping for 30 seconds"
sleep 30

# Chef user creation
# $ chef-server-ctl user-create USER_NAME FIRST_NAME LAST_NAME EMAIL 'PASSWORD' --filename FILE_NAME
/usr/bin/chef-server-ctl user-create $CHEFUSER $CHEFUSER $CHEFUSER $CHEFUSER@$cdomain \'$CHEFPASS\' --filename /etc/opscode/$CHEFUSER.pem
# Chef organization creation
# $ chef-server-ctl org-create short_name 'full_organization_name' --association_user user_name --filename ORGANIZATION-validator.pem
/usr/bin/chef-server-ctl org-create $CHEFORG \'$CHEFORG\' --association_user $CHEFUSER --filename /etc/opscode/$CHEFORG-validator.pem

# Copy and create certs
[ ! -f /etc/chef/$CHEFUSER.pem ] && cp /etc/opscode/$CHEFUSER.pem /etc/chef
[ ! -f /etc/chef/$CHEFORG-validator.pem ] && cp /etc/opscode/$CHEFORG-validator.pem /etc/chef/$CHEFORG-validator.pem

# Knife configuration
mkdir -p /root/.chef
[ ! -f /root/.chef/knife.rb ] && cp /etc/chef/knife.rb.default /root/.chef/knife.rb

# Create new client.rb file
[ ! -f /etc/chef/client.rb ] && cp /etc/chef/client.rb.default /etc/chef/client.rb

# Customize client.rb
sed -i "s/\HOSTNAME/$CLIENTNAME/g" /etc/chef/client.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.service.$cdomain:4443/organizations/$CHEFORG\"|" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/admin/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.service.$cdomain:4443/organizations/$CHEFORG\"|" /root/.chef/knife.rb
sed -i "s/client\.pem/admin\.pem/g" /root/.chef/knife.rb

# Configure LEADER
configure_leader

#rm -f /etc/opscode/chef-server.rb
rm -f /var/lock/leader-configuring.lock

# Copy dhclient hook
cp -f /usr/lib/redborder/lib/dhclient-enter-hooks /etc/dhcp/dhclient-enter-hooks

e_title "Configuring cgroups (first time), please wait..."

rb_configure_cgroups &>/dev/null

echo "Cgroups configured in /sys/fs/cgroup/redborder.slice/"

end_script=$(date +%s) # Save finish scrip time
runtime=$((end_script-start_script)) # Calculate duration of script
runtime_min=$(echo "scale=2; $runtime / 60" | bc -l) # Calculate duration of script in minutes

e_title "Leader Node configured! ($runtime_min minutes)"

date > /etc/redborder/cluster-installed.txt

