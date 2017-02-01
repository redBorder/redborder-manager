#!/bin/bash

echo "INFO: Executing rb_configure_initial_s3"
sleep 30 #Temporary sleep to mock script (for testing)

cat > /etc/serf/s3_query.json <<-_RBEOF_
{
    "event_handlers" : [
       "query:s3_conf=/usr/lib/redborder/bin/serf-response-file.sh /etc/redborder/s3_init_conf.yml"
    ]
}
_RBEOF_
systemd reload serf
serf tags -set s3=ready