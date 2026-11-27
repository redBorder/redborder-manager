#!/bin/bash

JSON="/var/chef/data/data_bag/passwords/nmspd-key-hashes.json"

source /etc/profile
source $RBLIB/rb_manager_functions.sh

FORCE=0
UPLOAD=0
ASK=1
CUSTOM_MAC=""

while getopts "fum:" name
do
  case $name in
    f) FORCE=1; ASK=0;;
    u) UPLOAD=1; ASK=0;;
    m) CUSTOM_MAC="$OPTARG";;
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
  if [ -n "$CUSTOM_MAC" ]; then
    NMSPMAC="$CUSTOM_MAC"
  else
    DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    if [ -n "$DEFAULT_IFACE" ] && [ -f "/sys/class/net/$DEFAULT_IFACE/address" ]; then
      NMSPMAC=$(cat "/sys/class/net/$DEFAULT_IFACE/address")
    else
      NMSPMAC=$(ip a | grep link/ether | head -n 1 | awk '{print $2}')
    fi
  fi
  if [ "x$NMSPMAC" == "x" ]; then
      NMSPMAC="$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):$(< /dev/urandom tr -dc a-f0-9 | head -c2 | sed 's/ //g'):"
  fi
  rm -f /var/chef/cookbooks/rb-nmsp/files/default/aes.keystore
  rm -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json
  mkdir -p /var/chef/cookbooks/rb-nmsp/files/default/

  if command -v rb-nmsp &>/dev/null || [ -x /usr/bin/rb-nmsp ]; then
    /usr/bin/rb-nmsp config-gen /var/chef/cookbooks/rb-nmsp/files/default/ /var/chef/data/data_bag/passwords/ "$NMSPMAC"
    if [ $? -eq 0 ]; then
        UPLOAD=1
    fi
  elif [ -f /usr/lib/redborder-nmsp/rb-nmsp.jar ]; then
    java -cp /usr/lib/redborder-nmsp/deps/*:/usr/lib/redborder-nmsp/rb-nmsp.jar net.redborder.nmsp.NmspConsumer config-gen /var/chef/cookbooks/rb-nmsp/files/default/ /var/chef/data/data_bag/passwords/ "$NMSPMAC"
    if [ $? -eq 0 ]; then
        UPLOAD=1
    fi
  fi
fi

if [ $UPLOAD -eq 1 -a -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json ]; then
  rvm gemset use default 
  env knife cookbook upload rbnmsp
  /usr/lib/redborder/bin/rb_upload_chef_data.sh -y -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json
fi

if [ -f /var/chef/data/data_bag/passwords/nmspd-key-hashes.json ]; then
  MAC=$(grep -o '"macAddress": *"[^"]*"' /var/chef/data/data_bag/passwords/nmspd-key-hashes.json | cut -d'"' -f4)
  SHA2=$(grep -o '"sha2KeyHashHex": *"[^"]*"' /var/chef/data/data_bag/passwords/nmspd-key-hashes.json | cut -d'"' -f4)
  SHA1=$(grep -o '"keyHashHex": *"[^"]*"' /var/chef/data/data_bag/passwords/nmspd-key-hashes.json | cut -d'"' -f4)

  echo ""
  echo "=========================================================================="
  echo "                     NMSP Authorization Details                           "
  echo "=========================================================================="
  echo "MAC Address:     $MAC"
  echo "SHA-256 Hash:    $SHA2"
  echo "SHA-1 Hash:      $SHA1"
  echo ""
  echo "Command to run on Cisco WLC CLI:"
  echo "  config auth-list add sha256-fingerprint $MAC $SHA2"
  echo "=========================================================================="
  echo ""
fi
