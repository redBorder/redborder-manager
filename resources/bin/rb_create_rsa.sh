#!/bin/bash

JSON="/var/www/rb-rails/config/rsa-ssh.json"

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

# If RSA key is configured, we ask if it can be overwrite
if [ $FORCE -eq 0 -a $ASK -eq 1 -a -f /var/www/rb-rails/config/rsa ]; then
  echo -n "The manager has a RSA key configured. Would you like to overwrite it? (y/N) "
  read OVR
fi

# Force overwrite RSA key
if [ "x$OVR" == "xy" -o "x$OVR" == "xY" ]; then
  rm -f /var/www/rb-rails/config/rsa
  ssh-keygen -t rsa -f /var/www/rb-rails/config/rsa -N ""
  chown webui:webui /var/www/rb-rails/config/rsa /var/www/rb-rails/config/rsa.pub
  echo "{
 \"id\": \"ssh\",
 \"username\": \"redborder\",
 \"public_rsa\": \"`cat /var/www/rb-rails/config/rsa.pub`\"
}" > $JSON

  knife data bag from file passwords $JSON
  rm -f $JSON
  echo "Checking NEW ssh rsa databag: "

  knife data bag show passwords ssh
  if [ $? -eq 0 ]; then
    UPLOAD=1
  fi
fi

if [ $UPLOAD -eq 1 -a -f /var/www/rb-rails/config/rsa ]; then
  upload_pem "rsa" "/var/www/rb-rails/config/rsa"
fi
