#!/bin/bash
# Script to download the darklist.json file needed to enrichment of rb_flow and rb_event on logstash/samza

source /etc/profile.d/rvm.sh

[ ! -f /tmp/memcached_pid ] && exit 0;

PID=$(/usr/sbin/pidof memcached)
[ $? -eq 1 ] && exit 0;

OLD_PID=$(</tmp/memcached_pid)
if [ $PID -ne $OLD_PID ];then
  echo $PID > /tmp/memcached_pid
  /usr/lib/redborder/bin/rb_refresh_darklist_memcached_keys &>/dev/null
fi
exit 0;