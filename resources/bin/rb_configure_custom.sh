#!/bin/bash
# redborder CUSTOM node initialization

source /etc/profile
source $RBLIB/rb_manager_functions.sh

########
# MAIN #
########

CHEFORG="redborder"
CLIENTNAME=$(hostname -s)
MANAGERMODE=$(serf members -status alive -name=$CLIENTNAME -format=json | jq -r .members[].tags.mode)

# Get cdomain
[ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 /etc/redborder/cdomain | tr '\n' ' ' | awk '{print $1}')

# Change resolv.conf file temporally
cp -f /etc/resolv.conf /etc/resolv.conf.init

# Check if consul ready and get IP
CONSULIP=$(serf members -tag consul=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
valid_ip $CONSULIP
if [ "x$?" == "x0" ]; then
  # Use Consul IP as DNS
  sed -i 's/nameserver .*/nameserver $CONSULIP/g' /etc/resolv.conf
  # Check if chef-server is registered in consul
  ret=$(curl $CONSULIP:8500/v1/catalog/services 2> /dev/null | jq .erchef)
else
  ret="null"
fi

if [ "x$ret" == "xnull" ]; then #If not chef-server registered
  # Get IP leader as a chef-server IP and Add chef-server IP to /etc/hosts
  IPLEADER=serf members -tag leader=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1
  grep -q erchef.service.${cdomain} /etc/hosts
  [ $? -ne 0 ] && echo "$IPLEADER   erchef.service.${cdomain}" >> /etc/hosts
fi

# Get chef validator and admin certificates
$RBBIN/serf-query-certificate.sh -q certificate-validator > /tmp/cert && mv /tmp/cert /etc/chef/redborder-validator.pem
$RBBIN/serf-query-certificate.sh -q certificate-admin > /tmp/cert && mv /tmp/cert /etc/chef/admin.pem

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
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.service.$cdomain:4443/organizations/$CHEFORG\"|" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/admin/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.service.$cdomain:4443/organizations/$CHEFORG\"|" /root/.chef/knife.rb
sed -i "s/client\.pem/admin\.pem/g" /root/.chef/knife.rb

# Create specific role for this node
e_title "Creating custom chef role"
mv /var/chef/data/role/manager_node.json /var/chef/data/role/$(hostname -s).json
# Change hostname in new role
sed -i "s/manager_node/$(hostname -s)/g" /var/chef/data/role/$(hostname -s).json
# Upload custom role
knife role -c /root/.chef/knife.rb from file /var/chef/data/role/$CLIENTNAME.json

# Create chef node and client from files in /etc/chef
e_title "Registering chef-client ..."
chef-client

# Adding chef roles to node
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[$CLIENTNAME]"

# MANAGER MODES
e_title "Configuring manager mode"
# Set manager role
[ "x$MANAGERMODE" == "x" ] && MANAGERMODE="custom"
$RBBIN/rb_set_mode.rb $MANAGERMODE

# Update timestamp #??#
$RBBIN/rb_update_timestamp.rb &>/dev/null

# Cleaning yum data and cache
yum clean all

# Multiple runs of chef-client
e_title "Configuring Chef-Client. Please wait...  "
e_title "redborder install run $(date)" #>>/root/.install-chef-client.log
chef-client #&>/root/.install-chef-client.log

echo "Custom Node configured!"
touch /etc/redborder/cluster-installed.txt
