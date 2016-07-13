#!/bin/bash
# redborder MASTER initialization

function configure_master(){
  # Check if master is configuring now
  #if [ -f /var/lock/master.lock ]; then
  #  echo "INFO: this manager has already been initialized"
  #  exit 0
  #fi
  #touch /var/lock/master.lock

  # COOKBOOKS
  mkdir -p /var/chef/cache/cookbooks/
  for n in zookeeper; do # cookbooks
    rsync -a /var/chef/cookbooks/${n}/ /var/chef/cache/cookbooks/$n
    # Upload cookbooks
    knife cookbook upload $n
  done

  # Customize DATA BAGs before uploading it #

  cat > /var/chef/data/data_bag/rBglobal/domain.json <<- _RBEOF_
{
  "id": "domain",
  "name": "${cdomain}"
}
_RBEOF_

  [ "x$PUBLICCDOMAIN" == "x" ] && PUBLICCDOMAIN="$cdomain"
  cat > /var/chef/data/data_bag/rBglobal/publicdomain.json <<- _RBEOF_
{
  "id": "publicdomain",
  "name": "${PUBLICCDOMAIN}"
}
_RBEOF_

  # More data bags ...
  # TODO

  # Upload chef data (ROLES, DATA BAGS, NODES, ENVIRONMENTS ...
  /usr/lib/redborder/bin/rb_upload_chef_data.sh -y

  # Adding role to node
  knife node -c /root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"

  # 

}

########
# MAIN #
########
# Set CDOMAIN
cdomain="redborder.cluster"
#[ -f /etc/redborder/cdomain ] && cdomain=$(head /etc/redborder/cdomain -n 1)
#[ "x$cdomain" == "x" ] && cdomain="redborder.cluster"

# Configure hostname with randon name
hostname "rb$(< /dev/urandom tr -dc a-z0-9 | head -c10 | sed 's/ //g')"
echo -e "127.0.0.1 `hostname` `hostname -s`" | sudo tee -a /etc/hosts

CLIENTNAME="admin" #for master node

#############################
# CHEF SERVER Configuration #
#############################

# Chef server initial configuration
HOME=/root /usr/bin/chef-server-ctl reconfigure #&>>/root/.install-chef-server.log
# Chef user creation
/usr/bin/chef-server-ctl user-create $CLIENTNAME $CLIENTNAME $CLIENTNAME $CLIENTNAME@redborder.com 'redborder' --filename /etc/opscode/$CLIENTNAME.pem
# Chef organization ceration
/usr/bin/chef-server-ctl org-create redborder 'redborder' --association_user $CLIENTNAME --filename /etc/opscode/redborder-validator.pem

# Copy and create certs
[ ! -f /etc/chef/$CLIENTNAME.pem ] && cp /etc/opscode/$CLIENTNAME.pem /etc/chef
[ ! -f /etc/chef/redborder-validator.pem ] && cp /etc/opscode/redborder-validator.pem /etc/chef/redborder-validator.pem
# Knife configuration
mkdir -p /root/.chef
[ ! -f /root/.chef/knife.rb ] && cp /etc/chef/knife.rb.default /root/.chef/knife.rb

# Create new client.rb file
[ ! -f /etc/chef/client.rb ] && cp /etc/chef/client.rb.default /etc/chef/client.rb

# Customize client.rb
sed -i "s/\HOSTNAME/admin/g" /etc/chef/client.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/redborder\"|" /etc/chef/client.rb
sed -i "s/client\.pem/admin\.pem/g" /etc/chef/client.rb

# Customize knife.rb
sed -i "s/\HOSTNAME/admin/g" /root/.chef/knife.rb
sed -i "s|^chef_server_url .*|chef_server_url  \"https://erchef.$cdomain/organizations/redborder\"|" /root/.chef/knife.rb
sed -i "s/client\.pem/admin\.pem/g" /root/.chef/knife.rb

# And in /etc/hosts
sed -i "s/\.redborder\.cluster/.${cdomain}/g" /etc/hosts

# Add erchef domain /etc/hosts
grep -q erchef.${cdomain} /etc/hosts
[ $? -ne 0 ] && echo "127.0.0.1   erchef.${cdomain}" >> /etc/hosts

echo "Registering chef-client ..."
/usr/bin/chef-client

# Configure MASTER
configure_master
