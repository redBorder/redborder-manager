#!/bin/bash

# Creates the passwords/hub encrypted data bag item (auth_token and
# registration_token of redborder-hub) on clusters installed before the
# tokens were generated per installation. It never overwrites an existing item.

source /etc/profile

KNIFE_CONF="/root/.chef/knife.rb"
SECRET_FILE="/etc/chef/encrypted_data_bag_secret"

if knife data bag show passwords hub -c $KNIFE_CONF --secret-file $SECRET_FILE &>/dev/null; then
  echo "passwords/hub data bag item already exists, nothing to do"
  exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf $TMPDIR' EXIT
chmod 0700 $TMPDIR

HUB_AUTH_TOKEN="`< /dev/urandom tr -dc A-Za-z0-9 | head -c64 | sed 's/ //g'`"
HUB_REGISTRATION_TOKEN="`< /dev/urandom tr -dc A-Za-z0-9 | head -c64 | sed 's/ //g'`"

cat > $TMPDIR/hub.json <<_RBEOF_
{
  "id": "hub",
  "auth_token": "$HUB_AUTH_TOKEN",
  "registration_token": "$HUB_REGISTRATION_TOKEN"
}
_RBEOF_

knife data bag from file passwords $TMPDIR/hub.json -c $KNIFE_CONF --secret-file $SECRET_FILE
RET=$?
if [ $RET -eq 0 ]; then
  echo "passwords/hub data bag item created"
else
  echo "Error creating passwords/hub data bag item"
fi
exit $RET
