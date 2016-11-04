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

}

function configure_db(){
  # Configuring database passwords
  [ "x$REDBORDERDBPASS" == "x" ] && REDBORDERDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  [ "x$DRUIDDBPASS" == "x" ] && DRUIDDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"

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

}

function configure_dataBags(){

  # Data bag encrypted key
  [ "x$DATABAGKEY" == "x" ] && DATABAGKEY="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
  echo $DATABAGKEY > /etc/chef/encrypted_data_bag_secret

  OCID_DBCFG="/var/opt/opscode/oc_id/config/database.yml"
  OCBIFROST_DBCFG="/var/opt/opscode/oc_bifrost/sys.config"
  CHEFMOVER_DBCFG="/var/opt/opscode/opscode-chef-mover/sys.config"

  # Obtaining chef database current configuration
  OPSCODE_DBHOST="`grep {db_host $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  [ "x$OPSCODE_DBHOST" == "x127.0.0.1" ] && OPSCODE_DBHOST=$IPLEADER
  OPSCODE_DBPORT="`grep {db_port $ERCHEFCFG |sed 's/.*{db_port, //' | sed 's/},//'`"
  OPSCODE_DBPASS="`grep {db_pass $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  OPSCODE_OCID_PASS="`grep password $OCID_DBCFG | sed 's/ password: //' | tr -d ' '`"
  OPSCODE_OCBIFROST_PASS="`grep db_pass $OCBIFROST_DBCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//' | sed 's/" },//'`"
  OPSCODE_CHEFMOVER_PASS="`grep db_pass $CHEFMOVER_DBCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//' | sed 's/" },//'`"

  # Obtaining chef cookbook storage current configuration
  S3KEY="`grep s3_access_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  S3SECRET="`grep s3_secret_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  S3URL="`grep s3_url, $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
  S3EXTERNALURL="`grep s3_external_url $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`" #CHECK when {s3_external_url, host_header},
  S3BUCKET="`grep s3_platform_bucket_name $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"

  ## Data bags for passwords ##
  mkdir -p /var/chef/data/data_bag/passwords/
  mkdir -p /var/chef/data/data_bag/rBglobal/

  ## S3 passwords ## TODO
  sed -i "s/s3.redborder.cluster/s3.$cdomain/" /var/chef/data/data_bag/passwords/s3_secrets.json

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
  "ocbifrost_pass": "$OPSCODE_OCBIFROST_PASS",
  "chefmover_pass": "$OPSCODE_CHEFMOVER_PASS"
}
_RBEOF_

  # S3 passwords
  cat > /var/chef/data/data_bag/passwords/s3.json <<-_RBEOF_
{
  "id": "s3",
  "s3_access_key_id": "$S3KEY",
  "s3_secret_key_id": "$S3SECRET",
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

  # Elasticache configuration
  cat > /var/chef/data/data_bag/rBglobal/elasticache.json <<-_RBEOF_
{
  "id": "elasticache",
  "cfg_address": "$ELASTICACHE_ADDRESS",
  "cfg_port": $ELASTICACHE_PORT
}
_RBEOF_

  #rb-webui secret key
#  RBWEBISECRET="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
#  cat > /var/chef/data/data_bag_encrypted/passwords/rb-webui_secret_token.json <<-_RBEOF_
#{
#  "id": "rb-webui_secret_token",
#  "secret": "$RBWEBISECRET"
#}
#_RBEOF_

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
  mkdir -p /var/chef/data/data_bag_encrypted/rBglobal
  cat > /var/chef/data/data_bag_encrypted/rBglobal/cluster.json <<-_RBEOF_
{
  "id": "cluster",
  "uuid": "$(cat /proc/sys/kernel/random/uuid)"
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

  # Chef server configuration
  ERCHEFCFG="/var/opt/opscode/opscode-erchef/sys.config"

  # Create specific role for this node
  e_title "Creating custom chef role"
  mv /var/chef/data/role/manager_node.json /var/chef/data/role/$(hostname -s).json
  # Change hostname in new role
  sed -i "s/manager_node/$(hostname -s)/g" /var/chef/data/role/$(hostname -s).json

  # Configure databases
  e_title "Configuring DataBases"
  configure_db

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
  listCookbooks="zookeeper kafka druid http2k cron memcached chef-server consul rb-manager" # The order matters!
  for n in $listCookbooks; do # cookbooks
    rsync -a /var/chef/cookbooks/${n}/ /var/chef/cache/cookbooks/$n
    # Uploadind cookbooks
    knife cookbook upload $n
  done

  e_title "Registering chef-client ..."
  /opt/opscode/bin/chef-client
  # Adding chef role to node
  knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
  knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[$CLIENTNAME]"

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

  # Multiple runs of chef-client
  e_title "Configuring Chef-Client. Please wait...  "
  e_title "redborder install run (1/3) $(date)" #>>/root/.install-chef-client.log
  chef-client #&>/root/.install-chef-client.log

  # Replace chef-server SV init scripts by systemd scripts
  /usr/bin/chef-server-ctl graceful-kill &>/dev/null
  if [ "$(ls -A /opt/opscode/service)" ]; then
    e_title "Stopping default private-chef-server services"
    /usr/bin/chef-server-ctl stop &>/dev/null
    e_title "Starting systemd chef-server services"
    for i in `ls /opt/opscode/service/`;do
      systemctl enable $i &>/dev/null && systemctl start $i &>/dev/null
      rm -rf /opt/opscode/service/$i &>/dev/null
    done
  fi

  e_title "redborder install run (2/3) $(date)" #>>/root/.install-chef-client.log
  chef-client #&>/root/.install-chef-client.log
  e_title "redborder install run (3/3) $(date)" #>>/root/.install-chef-client.log
  chef-client #&>/root/.install-chef-client.log
}

########
# MAIN #
########

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

# Chef server Installation
e_title "Installing Chef-Server from repository"
yum install -y redborder-chef-server

# Set chef-server.rb configuration file (S3)
[ -f /etc/redborder/chef-server-s3.rb ] && cat /etc/redborder/chef-server-s3.rb >> /etc/opscode/chef-server.rb && rm -f /etc/redborder/chef-server-s3.rb

# Set chef-server.rb configuration file (postgresql) and obtain database credentials
if [ -f /etc/redborder/chef-server-postgresql.rb ]; then
  cat /etc/redborder/chef-server-postgresql.rb >> /etc/opscode/chef-server.rb
  DB_ADMINUSER=$(cat /etc/redborder/chef-server-postgresql.rb | grep "db_superuser.]" | awk {'print $3'} | tr -d "\"")
  DB_ADMINPASS=$(cat /etc/redborder/chef-server-postgresql.rb | grep "db_superuser_password.]" | awk {'print $3'}| tr -d "\"")
  DB_HOST=$(cat /etc/redborder/chef-server-postgresql.rb | grep "vip.]" | awk {'print $3'}| tr -d "\"")
  rm -f /etc/redborder/chef-server-postgresql.rb
else
  DB_ADMINUSER="opscode-pgsql"
  DB_ADMINPASS="" #TODO
  DB_HOST=$IPLEADER
fi

# Set chef-server internal nginx port to 4443
echo "nginx['ssl_port'] = 4443" >> /etc/opscode/chef-server.rb

# Chef server initial configuration
e_title "Configuring Chef-Server"
/usr/bin/chef-server-ctl reconfigure #&>> /root/.install-chef-server.log

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

# Add erchef domain /etc/hosts (consul is not ready at this moment)
grep -q erchef.${cdomain} /etc/hosts
[ $? -ne 0 ] && echo "$IPLEADER   erchef.service.${cdomain}" >> /etc/hosts

# Modifying some default chef parameters (rabbitmq, postgresql) ## Check
# Rabbitmq # CHECK CHECK CHECK
sed -i "s/rabbit@localhost/rabbit@$CLIENTNAME/" /opt/opscode/embedded/cookbooks/private-chef/attributes/default.rb
mkdir -p /var/opt/opscode/rabbitmq/db
rm -f /var/opt/opscode/rabbitmq/db/rabbit@localhost.pid
ln -s /var/opt/opscode/rabbitmq/db/rabbit\@$CLIENTNAME.pid /var/opt/opscode/rabbitmq/db/rabbit@localhost.pid

# Permit all source IP address connecting to postgresql (if using chef local postgresql)
cat /etc/redborder/rb_init_conf.yml | grep postgresql &>/dev/null
if [ "x$?" != "x0" ]; then
  sed -i "s/^listen_addresses.*/listen_addresses = '*'/" /var/opt/opscode/postgresql/*/data/postgresql.conf
  cat > /var/opt/opscode/postgresql/9.2/data/pg_hba.conf <<-_RBEOF_
#TYPE   DATABASE        USER            CIDR-ADDRESS            METHOD
host  all  all 0.0.0.0/0 md5
_RBEOF_
fi

# Configure LEADER
configure_leader

#rm -f /etc/opscode/chef-server.rb
rm -f /var/lock/leader-configuring.lock

# Copy dhclient hook
cp -f /usr/lib/redborder/lib/dhclient-enter-hooks /etc/dhcp/dhclient-enter-hooks

e_title "Leader Node configured!"

touch /etc/redborder/cluster-installed.txt
