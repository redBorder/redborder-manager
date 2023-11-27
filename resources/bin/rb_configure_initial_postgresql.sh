#!/bin/bash

echo "INFO: Executing rb_configure_initial_postgresql"
cat > /etc/serf/postgresql_query.json <<-_RBEOF_
{
    "event_handlers" : [
       "query:postgresql_conf=/usr/lib/redborder/bin/serf-response-file.sh /etc/redborder/postgresql_init_conf.yml"
    ]
}
_RBEOF_

#Mandatory to load the new handler
echo "INFO: Restarting serf. Loading new handlers"
systemctl restart serf

#Configure postgresql service using chef-solo
echo "INFO: Configure PostgreSQL service using chef-solo"
chef-solo -c /var/chef/solo/postgresql-solo.rb -j /var/chef/solo/postgresql-attributes.json
if [ $? -ne 0 ] ; then
  echo "ERROR: chef-solo exited with code $?"
  exit 1
fi

cat > /etc/redborder/postgresql_init_conf.yml <<-_RBEOF_
---
postgresql:
  superuser: postgres
  password: ''
  host: master.postgresql.service
  port: '5432'
_RBEOF_

echo "INFO: Wait until tag postgresql is ready"
serf tags -set postgresql=ready
