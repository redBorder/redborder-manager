#!/bin/bash
# Script to download the darklist.json file needed to enrichment of rb_flow and rb_event on logstash

source /etc/profile.d/rvm.sh

DARK_LIST_FILE="/usr/share/darklist.json"

if [ ! -f DARK_LIST_FILE ]; then
  /usr/lib/redborder/bin/rb_update_darklist.sh
fi

entries=$(/usr/lib/redborder/scripts/rbcli.rb memcached keys dark | grep -c darklist)



if [ "$entries" -eq 0 ];then
  /usr/lib/redborder/scripts/rb_refresh_darklist_memcached_keys.rb > /dev/null
fi
