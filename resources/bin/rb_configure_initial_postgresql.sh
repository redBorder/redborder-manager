#!/bin/bash

echo "INFO: Executing rb_configure_initial_postgresql"
sleep 30 #Temporary sleep to mock script (for testing)

cat > /etc/serf/postgresql_query.json <<-_RBEOF_
{
    "event_handlers" : [
       "query:pg_conf=/usr/lib/redborder/bin/serf-response-file.sh /etc/redborder/pg_init_conf.yml"
    ]
}
_RBEOF_
systemd reload serf
serf tags -set postgresql=ready


