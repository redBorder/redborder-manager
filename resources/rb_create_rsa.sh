#!/bin/bash
#######################################################################    
# Copyright (c) 2014 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

# Author: Pablo Nebrera Herrera
# Script configura y genera llave RSA para comunicar el manager con los sensores.

#RBDIR=${RBDIR-/opt/rb}
JSON="/var/www/rb-rails/config/rsa-ssh.json"

if [ "x$UID" == "x0" ]; then
  KNIFECFG="/root/.chef/knife.rb"
else
  KNIFECFG="/var/www/rb-rails/config/knife.rb"
fi

source /etc/profile
source $RBBIN/bin/rb_manager_functions.sh

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

if [ $FORCE -eq 0 -a $ASK -eq 1 -a -f $RBDIR/var/www/rb-rails/config/rsa ]; then
  echo -n "The manager has a RSA key configured. Would you like to overwrite it? (y/N) "
  read OVR
fi

if [ "x$OVR" == "xy" -o "x$OVR" == "xY" ]; then
  rm -f /var/www/rb-rails/config/rsa
  ssh-keygen -t rsa -f /var/www/rb-rails/config/rsa -N ""
  chown rb-webui:rb-webui /var/www/rb-rails/config/rsa /var/www/rb-rails/config/rsa.pub
  mkdir -p /var/chef/data/data_bag_encrypted/passwords/
  echo "{
 \"id\": \"ssh\",
 \"username\": \"redBorder\",
 \"public_rsa\": \"`cat /var/www/rb-rails/config/rsa.pub`\"
}" > $JSON
  #$KNIFE data bag -c $KNIFECFG from file passwords $JSON --secret-file /etc/chef/encrypted_data_bag_secret --key ${CERT} -u ${CERTUSER} 
  $KNIFE data bag -c $KNIFECFG from file passwords $JSON --secret-file /etc/chef/encrypted_data_bag_secret
  rm -f $JSON
  echo "Checking NEW ssh rsa databag: "
  #$KNIFE data bag show passwords ssh -c $KNIFECFG --key ${CERT} -u ${CERTUSER}
  $KNIFE data bag show passwords ssh -c $KNIFECFG 
  if [ $? -eq 0 ]; then 
    UPLOAD=1
  fi
fi

if [ $UPLOAD -eq 1 -a -f /var/www/rb-rails/config/rsa ]; then
  upload_pem "rsa" "/var/www/rb-rails/config/rsa"    
fi
