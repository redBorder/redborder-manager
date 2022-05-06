#!/bin/bash
# Script to download the darklist.json file needed to enrichment of rb_flow and rb_event on logstash/samza

source /etc/profile.d/rvm.sh

entries=$(/usr/lib/redborder/scripts/red.rb memcached keys dark | grep -c darklist)

if [ "$entries" -eq 0 ];then
  /usr/lib/redborder/scripts/rb_refresh_darklist_memcached_keys.rb > /dev/null
fi
