#!/bin/bash

# Source functions library
source /etc/init.d/functions
source /etc/profile

function usage() {
    echo "$0 [ -l ] [ -c ] [ -s <service_name> ] [ -i ] [ -n <nodename> ]"
    echo "  * -l -> show logs after the wakeup"
    echo "  * -c -> wakeup full cluster"
    #echo "  * -i -> wakeup sensor nodes"
    #echo "  * -n <nodename> -> wakeup sensor/manager node name"
    echo "  * -s <service> -> wakeup manager with this service name enabled"
    exit 0
}

function wakeup() {
    /usr/bin/systemctl status chef-client &>/dev/null
    if [ $? -eq 0 ]; then
      echo -n "Waking up chef-client: "
    	/usr/bin/systemctl kill -s USR1 chef-client
      if [ $? -eq 0 ]; then
        success
      else
        failure
      fi
      echo
    else
      echo "chef-client is not running"
    fi
}

function wakeup_node_service() {
    SERVICE="$1"
    # Check if the asked service is enabled in this node
    /usr/lib/redborder/bin/rb_node_services -s $SERVICE &>/dev/null
    if [ "x$?" == "x0" ]; then
      wakeup
    fi
}

wmanagers=0
showlogs=0
service=""

while getopts "hcs:l" name
do
  case $name in
    h) usage;;
    c) wmanagers=1;;
    l) showlogs=1;;
    s) service="$OPTARG";;
  esac
done

if [ $wmanagers -eq 1 ]; then
  if [ "x$service" == "x" ]; then
    /usr/bin/serf query -timeout=250ms -no-ack wakeup-chef &>/dev/null
  else
    # TODO
    wakeup_node_service $service &>/dev/null #Only wakeup in local node if the service exists
  fi
else
  wakeup
fi

if [ $showlogs -eq 1 ]; then
  echo "Showing chef-client logs on $(hostname): "
  /usr/bin/journalctl -u chef-client -n 10 -f -o cat
fi
