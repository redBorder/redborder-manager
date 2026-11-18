#!/bin/bash

# Creates the hub tokens on clusters installed before they were generated per
# installation:
#   - passwords/hub (encrypted): auth_token, readable only by managers
#   - rBglobal/hub: registration_token, readable by proxies to enrol satellites
# Each item is created only if it is missing; existing items are never overwritten.

source /etc/profile

KNIFE_CONF="/root/.chef/knife.rb"
SECRET_FILE="/etc/chef/encrypted_data_bag_secret"

TMPDIR=$(mktemp -d)
trap 'rm -rf $TMPDIR' EXIT
chmod 0700 $TMPDIR

RET=0

# passwords/hub (encrypted)
if knife data bag show passwords hub -c $KNIFE_CONF --secret-file $SECRET_FILE &>/dev/null; then
  echo "passwords/hub data bag item already exists, nothing to do"
else
  HUB_AUTH_TOKEN="`< /dev/urandom tr -dc A-Za-z0-9 | head -c64 | sed 's/ //g'`"
  cat > $TMPDIR/passwords_hub.json <<_RBEOF_
{
  "id": "hub",
  "auth_token": "$HUB_AUTH_TOKEN"
}
_RBEOF_
  if knife data bag from file passwords $TMPDIR/passwords_hub.json -c $KNIFE_CONF --secret-file $SECRET_FILE; then
    echo "passwords/hub data bag item created"
  else
    echo "Error creating passwords/hub data bag item"
    RET=1
  fi
fi

# rBglobal/hub (plain)
if knife data bag show rBglobal hub -c $KNIFE_CONF &>/dev/null; then
  echo "rBglobal/hub data bag item already exists, nothing to do"
else
  HUB_REGISTRATION_TOKEN="`< /dev/urandom tr -dc A-Za-z0-9 | head -c64 | sed 's/ //g'`"
  cat > $TMPDIR/rbglobal_hub.json <<_RBEOF_
{
  "id": "hub",
  "registration_token": "$HUB_REGISTRATION_TOKEN"
}
_RBEOF_
  if knife data bag from file rBglobal $TMPDIR/rbglobal_hub.json -c $KNIFE_CONF; then
    echo "rBglobal/hub data bag item created"
  else
    echo "Error creating rBglobal/hub data bag item"
    RET=1
  fi
fi

exit $RET
