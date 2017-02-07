#!/bin/bash

#
# Function to get available modes for a service
#
function candidateModes() {
  SERVICE=$1

  s3_modes="s3|full"
  postgresql_modes="postgresql|full"

  CANDIDATE_MODES=$(eval echo \$${SERVICE}_modes)
}

##################################################
# MAIN EXECUTION
##################################################

#Default parameter values
SERF_BIN=serf
LEADER_TAG="leader=wait"
READY_TAG="consul=ready"
REQUIRED_KEY="_required="
s3_TAG="s3_required=true"
postgresql_TAG="postgresql_required=true"
S3_CANDIDATES_TAG="mode=s3|full"
PG_CANDIDATES_TAG="mode=postgres|full"
CANDIDATE_MODES=""

leader_tag_key=$(echo $LEADER_TAG | cut -d '=' -f 1)

#Check if leader_tag_key or READY_TAG exists in a node. If not, keep waiting...
serf members | grep -q $leader_tag_key || serf members -tag $READY_TAG | grep -q $READY_TAG
while [ "x$?" == "x1" ] ; do
  echo "INFO: Waiting for a leader..."
  sleep 5
  serf members | grep -q $leader_tag_key || serf members -tag $READY_TAG | grep -q $READY_TAG
done

#Check if LEADER_TAG is set in a node
serf members -tag $LEADER_TAG | grep -q $LEADER_TAG
if [ "x$?" == "x0" ] ; then
  echo "INFO: detected that leader is in wait state"
  counter=0
  #Check if exists any REQUIRED_KEY in a node. If not, keep waiting...
  serf members | grep -q $REQUIRED_KEY
  while [ "x$?" == "x1" -a $counter -le 10 ] ; do
    echo "INFO: Waiting for a required tag..."
    sleep 2
    let counter=counter+1
    serf members | grep -q $REQUIRED_KEY
  done
  [ $counter -gt 10 ] && echo "WARNING: Required key tag not found while leader is waiting" && exit 0

  #Check if any of S3_TAG or PG_TAG are true
  serf members -tag $s3_TAG | grep -q $s3_TAG || serf members -tag $postgres_TAG | grep -q $postgres_TAG
  if [ "x$?" == "x0" ] ; then
    serviceList=(s3 postgresql)
    for service in ${serviceList[@]}; do
      #Check if any service is required is required
      serf members -tag $(eval echo \$${service}_TAG) | grep -q $(eval echo \$${service}_TAG)
      if [ "x$?" == "x0" ] ; then
        #Get candidate modes
        candidateModes $service
        #Call choose-leader and set service tag to ready
        serf-choose-leader.sh -r leader=inprogress -t $service=inprogress -c mode=$CANDIDATE_MODES -l rb_configure_initial_$service.sh
      fi
    done
  fi
fi
