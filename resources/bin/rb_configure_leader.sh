#!/bin/bash
# redborder LEADER node initialization
# This node is the first of the cluster. It install and configure chef-server

source /etc/profile
source $RBLIB/rb_manager_functions.sh

function configure_db(){
    ########################
    # Configuring database #
    ########################
    echo "Initiating database: "
    ldconfig &>/dev/null

    OCID_DBCFG="/var/opt/opscode/oc_id/config/database.yml"
    OCBIFROST_DBCFG="/var/opt/opscode/oc_bifrost/sys.config"
    CHEFMOVER_DBCFG="/var/opt/opscode/opscode-chef-mover/sys.config"

    # Configuring passwords
    [ "x$REDBORDERDBPASS" == "x" ] && REDBORDERDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"

    # Chef database configurations
    OPSCODE_DBPASS="`grep db_pass $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    OPSCODE_DBHOST="`grep db_host $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    OPSCODE_DBPORT="`grep db_port $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    OPSCODE_OCID_PASS="`grep password $OCID_DBCFG | sed 's/ password: //' | tr -d ' '`"
    OPSCODE_OCBIFROST_PASS="`grep db_pass $OCBIFROST_DBCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//' | sed 's/" },//'`"
    OPSCODE_CHEFMOVER_PASS="`grep db_pass $CHEFMOVER_DBCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//' | sed 's/" },//'`"

    S3KEY="`grep s3_access_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    S3SECRET="`grep s3_secret_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    S3URL="`grep s3_url, $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    S3EXTERNALURL="`grep s3_external_url $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    S3BUCKET="`grep s3_platform_bucket_name $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"

    #BOOKSHELFKEY="`grep s3_access_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"
    #BOOKSHELFSECRET="`grep s3_secret_key_id $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/"},[ ]*$//'`"

    #RABBITMQPASS="`grep rabbitmq_password $ERCHEFCFG | sed 's/[^"]*"//' | sed 's/">>},[ ]*$//'`"

    #PGPOOLPASS=""
    #DRUIDDBPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"
    #OOZIEPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c128 | sed 's/ //g'`"

    #pgpool passwords #Check recovery SQL files. Not found!!!
    #[ -f /usr/share/pgpool-II/pgpool-recovery.sql ] && su - opscode-pgsql -s /bin/bash -c "psql -f /usr/share/pgpool-II/pgpool-recovery.sql template1"
    #[ -f /usr/share/pgpool-II/pgpool-regclass.sql ] && su - opscode-pgsql -s /bin/bash -c "psql -f /usr/share/pgpool-II/pgpool-regclass.sql template1"

    #for n in redborder ; do # only redborder database?
    #  su - opscode-pgsql -s /bin/bash -c "dropdb $n &>/dev/null"
    #  su - opscode-pgsql -s /bin/bash -c "createdb --encoding=UTF8 --template=template0 $n"
    #  [ -f /usr/share/pgpool-II/pgpool-recovery.sql ] && su - opscode-pgsql -s /bin/bash -c "psql -f /usr/share/pgpool-II/pgpool-recovery.sql $n"
    #  [ -f /usr/share/pgpool-II/pgpool-regclass.sql ] && su - opscode-pgsql -s /bin/bash -c "psql -f /usr/share/pgpool-II/pgpool-regclass.sql $n"
    #done

    #su - opscode-pgsql -s /bin/bash -c "dropdb druid &>/dev/null"
    #su - opscode-pgsql -s /bin/bash -c "createdb druid"
    #su - opscode-pgsql -s /bin/bash -c "dropdb oozie &>/dev/null"
    #su - opscode-pgsql -s /bin/bash -c "createdb oozie"

    # Generate MD5 password for pgpool
    #if [ ! -f /etc/pgpool-II/pool_passwd ]; then
    #  mkdir -p /etc/pgpool-II/ && rm -f /etc/pgpool-II/pool_passwd
    #  touch /etc/pgpool-II/pool_passwd
    #  [ ! -f /etc/pgpool-II/pgpool.conf -a -f /etc/pgpool-II/pgpool.conf.default ] && cp /etc/pgpool-II/pgpool.conf.default /etc/pgpool-II/pgpool.conf
    #  pg_md5 --md5auth --username=redborder "${REDBORDERDBPASS}" -f /etc/pgpool-II/pgpool.conf
    #  pg_md5 --md5auth --username=druid "${DRUIDDBPASS}" -f /etc/pgpool-II/pgpool.conf
    #  pg_md5 --md5auth --username=oozie "${OOZIEPASS}" -f /etc/pgpool-II/pgpool.conf
    #  pg_md5 --md5auth --username=opscode_chef "${OPSCODE_CHEFPASS}" -f /etc/pgpool-II/pgpool.conf
    #fi

    #PGPOOLPASS="`< /dev/urandom tr -dc A-Za-z0-9 | head -c35 | sed 's/ //g'`"
    #PGPOOLPASSMD5="`pg_md5 $PGPOOLPASS`"
    #REDBORDERDBPASSMD5="`cat /etc/pgpool-II/pool_passwd | grep "^redborder:"|tr ':' ' ' | awk '{print $2}'`"
    #DRUIDDBPASSMD5="`cat /etc/pgpool-II/pool_passwd | grep "^druid:"|tr ':' ' ' | awk '{print $2}'`"
    #OOZIEPASSMD5="`cat /etc/pgpool-II/pool_passwd | grep "^oozie:"|tr ':' ' ' | awk '{print $2}'`"
    #OPSCODE_CHEFPASSMD5="`cat /etc/pgpool-II/pool_passwd | grep "^opscode_chef:"|tr ':' ' ' | awk '{print $2}'`"

    #su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER redborder WITH PASSWORD '$REDBORDERDBPASS';\" | psql -U opscode-pgsql"
    #su - opscode-pgsql -s /bin/bash -c "echo \"ALTER  USER redborder WITH PASSWORD '$REDBORDERDBPASS';\" | psql -U opscode-pgsql" &>/dev/null
    #su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER druid WITH PASSWORD '$DRUIDDBPASS';\" | psql -U opscode-pgsql"
    #su - opscode-pgsql -s /bin/bash -c "echo \"ALTER  USER druid WITH PASSWORD '$DRUIDDBPASS';\" | psql -U opscode-pgsql"
    #su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER oozie WITH PASSWORD '$OOZIEPASS';\" | psql -U opscode-pgsql"
    #su - opscode-pgsql -s /bin/bash -c "echo \"ALTER  USER oozie WITH PASSWORD '$OOZIEPASS';\" | psql -U opscode-pgsql"

    echo "Configuring first secrets"
}

function configure_dataBags(){

  ## Data bags for passwords ##
  mkdir -p /var/chef/data/data_bag_encrypted/passwords/

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
  "chefmover_pass": "$OPSCODE_CHEFMOVER_PASS",
}
_RBEOF_

## DB opscode (chef) passwords
  cat > /var/chef/data/data_bag/passwords/s3_chef.json <<-_RBEOF_
{
  "id": "s3_chef",
  "s3_access_key_id": "$S3KEY",
  "s3_secret_key_id": "$S3SECRET",
  "s3_url": "$S3URL",
  "s3_external_url": "$S3EXTERNALURL",
  "s3_platform_bucket_name": "$S3BUCKET"
}
_RBEOF_

# rabbitmq passwords
#cat > /var/chef/data/data_bag_encrypted/passwords/rabbitmq.json <<-_RBEOF_
#{
#  "id": "rabbitmq",
#  "username": "chef",
#  "pass": "$RABBITMQPASS"
#}
#_RBEOF_
#
## booksheld passwords
#cat > /var/chef/data/data_bag_encrypted/passwords/opscode-bookshelf-admin.json <<-_RBEOF_
#{
#  "id": "opscode-bookshelf-admin",
#  "key_id": "$BOOKSHELFKEY",
#  "key_secret": "$BOOKSHELFSECRET"
#}
#_RBEOF_

  # DB redborder passwords
#  cat > /var/chef/data/data_bag_encrypted/passwords/db_redborder.json <<-_RBEOF_
#{
#  "id": "db_redborder",
#  "username": "redborder",
#  "database": "redborder",
#  "hostname": "$OPSCODE_DBHOST",
#  "port": 5432,
#  "pass": "$REDBORDERDBPASS",
#  "md5_pass": "$REDBORDERDBPASSMD5"
#}
#_RBEOF_

  # DB druid passwords
#  cat > /var/chef/data/data_bag_encrypted/passwords/db_druid.json <<-_RBEOF_
#{
#  "id": "db_druid",
#  "username": "druid",
#  "database": "druid",
#  "hostname": "postgresql.${cdomain}",
#  "port": 5432,
#  "pass": "$DRUIDDBPASS",
#  "md5_pass": "$DRUIDDBPASSMD5"
#}
#_RBEOF_

  # DB oozie passwords
#  cat > /var/chef/data/data_bag_encrypted/passwords/db_oozie.json <<-_RBEOF_
#{
#  "id": "db_oozie",
#  "username": "oozie",
#  "database": "oozie",
#  "hostname": "postgresql.${cdomain}",
#  "port": 5432,
#  "pass": "$OOZIEPASS",
#  "md5_pass": "$OOZIEPASSMD5"
#}
#_RBEOF_

  # pgpool passwords
#  if [ "x$PGPOOLPASS" != "x" ]; then
#    cat > /var/chef/data/data_bag_encrypted/passwords/pgp_pgpool.json <<-_RBEOF_
#{
#  "id": "pgp_pgpool",
#  "username": "pgpool",
#  "pass": "$PGPOOLPASS",
#  "md5_pass": "$PGPOOLPASSMD5"
#}
#_RBEOF_
#  fi

  # vrrp passwords
#  if [ "x$VRRPPASS" != "x" ]; then
#  cat > /var/chef/data/data_bag_encrypted/passwords/vrrp.json <<-_RBEOF_
#{
#  "id": "vrrp",
#  "username": "vrrp",
#  "start_id": "$[ ( $RANDOM % ( $[ 200 - 10 ] + 1 ) ) + 10 ]",
#  "pass": "$VRRPPASS"
#}
#_RBEOF_
#  fi

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

function configure_leader(){
  # Check if leader is configuring now
  if [ -f /var/lock/leader-configuring.lock ]; then
    echo "INFO: this manager is being configuring just now!"
    exit 0
  fi
  touch /var/lock/leader-configuring.lock

  # Chef server configuration
  ERCHEFCFG="/var/opt/opscode/opscode-erchef/sys.config" # old app.config

  # Configure database
  e_title "Configuring Database"
  configure_db

  # Create specific role for this node
  e_title "Creating custom chef role"
  mv /var/chef/data/role/manager_node.json /var/chef/data/role/$(hostname -s).json
  # Change hostname in new role
  sed -i "s/manager_node/$(hostname -s)/g" /var/chef/data/role/$(hostname -s).json

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
  listCookbooks="zookeeper kafka druid nomad http2k cron memcached chef-server riak rb-manager" # The order matters!
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
  $RBBIN/rb_set_mode.rb $MANAGERMODE

  # Update timestamp #??#
  $RBBIN/rb_update_timestamp.rb &>/dev/null

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
  e_title "redborder install run $(date)" #>>/root/.install-chef-client.log
  chef-client #&>/root/.install-chef-client.log

  # Replace chef-server SV init scripts by systemd scripts
  /usr/bin/chef-server-ctl graceful-kill
  if [ "$(ls -A /opt/opscode/service)" ]; then
    e_title "Stopping default private-chef-server services"
    /usr/bin/chef-server-ctl stop
    for i in `ls /opt/opscode/service/`;do
      e_title "Starting systemd chef-server services"
      systemctl enable $i && systemctl start $i
      rm -rf /opt/opscode/service/$i
    done
  fi

  e_title "redborder install run $(date)" #>>/root/.install-chef-client.log
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

# Set chef-server.rb configuration file (S3 and postgresql)
[ -f /etc/redborder/chef-server-s3.rb ] && cat /etc/redborder/chef-server-s3.rb >> /etc/opscode/chef-server.rb
[ -f /etc/redborder/chef-server-postgresql.rb ] && cat /etc/redborder/chef-server-postgresql.rb >> /etc/opscode/chef-server.rb

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
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/$CHEFORG\"|" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/admin/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/$CHEFORG\"|" /root/.chef/knife.rb
sed -i "s/client\.pem/admin\.pem/g" /root/.chef/knife.rb

# Add erchef domain /etc/hosts
grep -q erchef.${cdomain} /etc/hosts
[ $? -ne 0 ] && echo "$IPLEADER   erchef.${cdomain}" >> /etc/hosts

# Modifying some default chef parameters (rabbitmq, postgresql) ## Check
# Rabbitmq # Check
sed -i "s/rabbit@localhost/rabbit@$CLIENTNAME/" /opt/opscode/embedded/cookbooks/private-chef/attributes/default.rb
mkdir -p /var/opt/opscode/rabbitmq/db
rm -f /var/opt/opscode/rabbitmq/db/rabbit@localhost.pid
ln -s /var/opt/opscode/rabbitmq/db/rabbit\@$CLIENTNAME.pid /var/opt/opscode/rabbitmq/db/rabbit@localhost.pid

# Permit all IP address source in postgresql
sed -i "s/^listen_addresses.*/listen_addresses = '*'/" /var/opt/opscode/postgresql/*/data/postgresql.conf

# Configure LEADER
configure_leader

rm -f /var/lock/leader-configuring.lock
echo "Leader Node configured!"
touch /etc/redborder/cluster-installed.txt
