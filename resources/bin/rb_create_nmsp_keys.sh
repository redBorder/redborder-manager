#!/bin/bash

JSON="/var/chef/data/data_bag/passwords/nmspd-key-hashes.json"

source /etc/profile
source $RBLIB/rb_manager_functions.sh

FORCE=0
UPLOAD=0
ASK=1

while getopts "fu" name
do
  case $name in
    f) FORCE=1; ASK=0;;
    u) UPLOAD=1; ASK=0;;
  esac
done

if [ $FORCE -eq 0 -a $UPLOAD -eq 1 ]; then
  OVR="n"
else
  OVR="y"
fi

# If Keys was configured, we ask if it can be overwrite
if [ $FORCE -eq 0 -a $ASK -eq 1 -a -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json ]; then
  echo -n "The manager has a RSA key configured. Would you like to overwrite it? (y/N) "
  read OVR
fi

# Force overwrite NMSP keys
if [ "x$OVR" == "xy" -o "x$OVR" == "xY" ]; then
  if [ -f /usr/lib/redborder-nmsp/rb-nmsp.jar ]; then
    NMSPMAC=$(ip a | grep link/ether | tail -n 1 | awk '{print $2}')
    if [ "x$NMSPMAC" == "x" ]; then
        NMSPMAC="$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):"
    fi
    rm -f /var/chef/cookbooks/rb-nmsp/files/default/aes.keystore
    rm -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json
    mkdir -p /var/chef/cookbooks/rb-nmsp/files/default/
    java -cp /usr/lib/redborder-nmsp/deps/*:/usr/lib/redborder-nmsp/rb-nmsp.jar net.redborder.nmsp.NmspConsumer config-gen /var/chef/cookbooks/rb-nmsp/files/default/ /var/chef/data/data_bag/passwords/ $NMSPMAC
    
    if [ $? -eq 0 ]; then
        UPLOAD=1
    fi
  fi
fi

if [ $UPLOAD -eq 1 -a -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json ]; then
  /usr/lib/redborder/bin/rb_upload_chef_data.sh -y -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json
fi
