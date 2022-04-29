#!/bin/bash
# Script to download the darklist.json file needed to enrichment of rb_flow and rb_event on logstash/samza

source /etc/profile.d/rvm.sh

LOG_FILE="/var/log/rb_update_darklist.log"
TMP_FILE="/tmp/darklist.json"
DARKLIST_FILE="/usr/share/darklist.json"

#Download the /tmp/darklist.json file
java -cp /usr/lib/darklist-updated/darklist-updated.jar net.redborder.darklistupdate.DarklistService $TMP_FILE >> $LOG_FILE &> /dev/null

# If the file was not download.. we exit
if [ ! -f $TMP_FILE ]; then exit 0; fi

# If there is a previous file..
if [ -f $DARK_LIST_FILE ]; then
  #Check if the md5 changes..
  #If didnt change, dont do anything.. exit
  if cmp --silent "$TMP_FILE" "$DARKLIST_FILE"; then
    echo 'nothing to do!' >> $LOG_FILE
    exit 0;
  fi
fi

cp $TMP_FILE $DARKLIST_FILE >> $LOG_FILE
rb_manager_utils.sh -c -n all -p $DARKLIST_FILE >> $LOG_FILE
rb_refresh_darklist_memcached_keys &>/dev/null

PID=$(pidof memcached)
if [ $? -eq 0 ]; then
  echo $PID > /tmp/memcached_pid
fi

exit 0;