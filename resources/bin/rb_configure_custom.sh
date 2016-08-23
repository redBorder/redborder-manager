#!/bin/bash
# redborder CUSTOM node initialization

source /etc/profile

function configure_custom(){
   echo "Configure CUSTOM node"
}

########
# MAIN #
########

CLIENTNAME=`hostname -s`
CHEFORG="redborder" # Chef org

# Get cdomain
[ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 /etc/redborder/cdomain | tr '\n' ' ' | awk '{print $1}')

# Get MASTER IP and add to /etc/hosts
# Proteger por si aun no esta ready el master #TODO
IPMASTER=`serf members -status alive -tag master=ready -format=json | jq -r .members[].addr | cut -d ":" -f 1`
grep -q erchef.${cdomain} /etc/hosts
[ $? -ne 0 ] && echo "$IPMASTER   erchef.${cdomain}" >> /etc/hosts

# Get chef validator and admin certificates 
$RBBIN/serf-query-certificate.sh -q certificate-validator > /etc/chef/redborder-validator.pem
$RBBIN/serf-query-certificate.sh -q certificate-admin > /etc/chef/admin.pem

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
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/$CHEFORG\"|" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/admin/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/$CHEFORG\"|" /root/.chef/knife.rb
sed -i "s/client\.pem/admin\.pem/g" /root/.chef/knife.rb

# Upload role
knife role -c /root/.chef/knife.rb from file /var/chef/data/role/$CLIENTNAME.json

# Create chef node and client from files in /etc/chef
/usr/bin/chef-client

# Adding role to node
knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[$CLIENTNAME]"

# MANAGER ROLES (modes)
[ -f /etc/chef/initialrole ] && initialrole=$(head /etc/chef/initialrole -n 1)
[ "x$initialrole" == "x" ] && initialrole="custom"
# Set manager role
$RBBIN/rb_set_mode.rb $initialrole
$RBBIN/rb_update_timestamp.rb &>/dev/null

# Cleaning yum data and cache
yum clean all
echo "Configuring chef client (first time). Please wait...  "
echo "###########################################################" #>>/root/.install-chef-client.log
echo "redborder install 1/3 run $(date)" #>>/root/.install-chef-client.log
echo "###########################################################" #>>/root/.install-chef-client.log
chef-client #&>/root/.install-chef-client.log
echo "" #>>/root/.install-chef-client.log
echo "###########################################################" #>>/root/.install-chef-client.log
echo "redborder install 2/3 run $(date)" #>>/root/.install-chef-client.log
echo "###########################################################" #>>/root/.install-chef-client.log
chef-client #&>>/root/.install-chef-client.log
echo "" #>>/root/.install-chef-client.log
echo "###########################################################" #>>/root/.install-chef-client.log
echo "redborder install 3/3 run $(date)" #>>/root/.install-chef-client.log
echo "###########################################################" #>>/root/.install-chef-client.log
chef-client #&>>/root/.install-chef-client.log
echo "" #>>/root/.install-chef-client.log
