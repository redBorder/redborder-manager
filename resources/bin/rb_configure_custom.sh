#!/bin/bash
# redborder CUSTOM node initialization

source /etc/profile
source $RBLIB/rb_manager_functions.sh

########
# MAIN #
########
start_script=$(date +%s) # Save init time

CHEFORG="redborder"
CLIENTNAME=$(hostname -s)
MANAGERMODE=$(serf members -status alive -name=$CLIENTNAME -format=json | jq -r .members[].tags.mode)

# Get cdomain
[ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 $RBETC/cdomain | tr '\n' ' ' | awk '{print $1}')

# Change resolv.conf file temporally
cp -f /etc/resolv.conf $RBETC/original_resolv.conf

# Check if consul ready and get IP
CONSULIP=$(serf members -tag consul=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
valid_ip $CONSULIP
if [ "x$?" == "x0" ]; then
  # Use correct search domain
  sed -i "s/search .*/search node.$cdomain service.$cdomain $cdomain/g" /etc/resolv.conf
  # Use Consul IP as DNS
  sed -i "s/nameserver .*/nameserver $CONSULIP/g" /etc/resolv.conf
  # Check if chef-server is registered in consul
  ret=$(curl $CONSULIP:8500/v1/catalog/services 2> /dev/null | jq .erchef)
  s3_ret=$(curl $CONSULIP:8500/v1/catalog/services 2> /dev/null | jq .s3)
else
  ret="null"
  s3_ret="null"
fi

if [ "x$ret" == "xnull" -o "x$ret" == "x" ]; then #If not chef-server registered
  # Get IP leader as a chef-server IP and Add chef-server IP to /etc/hosts
  IPLEADER=$(serf members -tag leader=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
  grep -q erchef.service.${cdomain} /etc/hosts
  [ $? -ne 0 ] && echo "$IPLEADER   erchef.service.${cdomain}" >> /etc/hosts
fi

if [ "x$s3_ret" == "xnull" -o "x$s3_ret" == "x" ]; then #If not s3 registered
  # Get IP s3 as a s3 service IP and Add s3 IP to /etc/hosts
  IP_S3=$(serf members -tag s3=ready | awk {'print $2'} |cut -d ":" -f 1 | head -n1)
  grep -q s3.service.${cdomain} /etc/hosts
  [ $? -ne 0 ] && echo "$IP_S3   s3.service.${cdomain}" >> /etc/hosts
fi

IP_PG=$(serf members -tag postgresql=ready | awk {'print $2'} | cut -d ":" -f 1 | head -n1)
echo "$IP_PG master.postgresql.service master.postgresql.service.${cdomain}" | sudo tee -a /etc/hosts > /dev/null

# Get chef validator and admin certificates
$RBBIN/serf-query-file -q certificate-validator > /tmp/cert && mv /tmp/cert /etc/chef/redborder-validator.pem
[ "x$?" != "x0" ] && error_title "ERROR getting redborder-validator.pem Chef certificate" && exit 1

$RBBIN/serf-query-file -q certificate-admin > /tmp/cert && mv /tmp/cert /etc/chef/admin.pem
[ "x$?" != "x0" ] && error_title "ERROR getting admin.pem Chef certificate" && exit 1

$RBBIN/serf-query-file -q databag-secret > /tmp/encrypted_data_bag_secret && mv /tmp/encrypted_data_bag_secret /etc/chef/encrypted_data_bag_secret
[ "x$?" != "x0" ] && error_title "ERROR getting encrypted_data_bag_secret Chef data bag secret" && exit 1

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
chef-client --chef-license accept

# Adding chef roles to node
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[$CLIENTNAME]"

# MANAGER MODES
e_title "Configuring manager mode"
# Set manager role
[ "x$MANAGERMODE" == "x" ] && MANAGERMODE="custom"
$RBBIN/rb_set_mode $MANAGERMODE

# Update timestamp #??#
$RBBIN/rb_update_timestamp &>/dev/null

# Cleaning yum data and cache
yum clean all

# Multiple runs of chef-client
e_title "Configuring Chef-Client. Please wait...  "
e_title "redborder install run $(date)" #>>/root/.install-chef-client.log
chef-client #&>/root/.install-chef-client.log
# Set client.pem as readable
chmod a+r /etc/chef/client.pem

#Add client to admins group
knife group add client `hostname -s` admins &>/dev/null

e_title "Enabling chef-client service"
systemctl enable chef-client
systemctl start chef-client

# Copy dhclient hook
cp -f /usr/lib/redborder/lib/dhclient-enter-hooks /etc/dhcp/dhclient-enter-hooks

e_title "Configuring cgroups (first time), please wait..."

rb_configure_cgroups &>/dev/null

echo "Cgroups configured in /sys/fs/cgroup/redborder.slice/"

end_script=$(date +%s) # Save finish scrip time
runtime=$((end_script-start_script)) # Calculate duration of script
runtime_min=$(echo "scale=2; $runtime / 60" | bc -l) # Calculate duration of script in minutes

e_title "Custom Node configured! ($runtime_min minutes)"
date > /etc/redborder/cluster-installed.txt
