#!/bin/bash
# redborder SLAVE initialization

function configure_master(){
   echo "Configure SLAVE node"
}

########
# MAIN #
########

#sys_manager_rsa=$1 # Se obtiene con SERF
#sys_manager_mode=$2

# Set CDOMAIN
cdomain="redborder.cluster"
#[ -f /etc/redborder/cdomain ] && cdomain=$(head /etc/redborder/cdomain -n 1)
#[ "x$cdomain" == "x" ] && cdomain="redborder.cluster"

# Set RSA keys for root user
echo -e  'y\n'|ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa

# Configure hostname with randon name
CLIENTNAME=`hostname "rb$(< /dev/urandom tr -dc a-z0-9 | head -c10 | sed 's/ //g')"`
echo -e "127.0.0.1 `hostname` `hostname -s`" | sudo tee -a /etc/hosts

# Get MASTER IP and add to /etc/hosts
IPMASTER=`serf members -status alive -tag master=yes -format=json | jq -r .members[].addr | cut -d ":" -f 1`
echo "$IPMASTER   erchef.${cdomain}" >> /etc/hosts

# Files to download from master node
files_scp="/etc/chef/redborder-validator.pem"

# Downloading CERTs from master
if [ "x$IPMASTER" != "x" -a -f $sys_manager_rsa ]; then
  scp -i $sys_manager_rsa -o StrictHostKeyChecking=no -q redborder@${IPMASTER}:"$files_scp" /etc/chef;
else
  echo -n "INFO: You are going to connect via ssh to redborder@${IPMASTER}"
  scp -o StrictHostKeyChecking=no -q root@${IPMASTER}:"$files_scp" /etc/chef;
fi

#############################
# CHEF CLIENT Configuration #
#############################

# Knife configuration
mkdir -p /root/.chef
[ ! -f /root/.chef/knife.rb ] && cp /etc/chef/knife.rb.default /root/.chef/knife.rb
# Create new client.rb file
[ ! -f /etc/chef/client.rb ] && cp /etc/chef/client.rb.default /etc/chef/client.rb

# Customize client.rb
sed -i "s/\HOSTNAME/$CLIENTNAME/g" /etc/chef/client.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/redborder\"|" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/$CLIENTNAME/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/redborder\"|" /root/.chef/knife.rb

# Create chef node and client from files in /etc/chef
/usr/bin/chef-client

# Adding role to node
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
