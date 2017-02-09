#!/bin/bash

echo "INFO: Executing rb_configure_initial_postgresql"
sleep 30 #Temporary sleep to mock script (for testing)

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

echo "INFO: Wait until tag postgresql is ready"
serf tags -set postgresql=ready
while [ "x$?" != "x0" ]; do
  sleep 2
  serf tags -set postgresql=ready
done
