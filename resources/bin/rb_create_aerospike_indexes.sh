#!/bin/bash

# Create Aerospike indexes if not exists

function create_index() {
  local namespace=$1
  local set=$2
  local bin=$3
  local index_name=$4
  local index_type=$5

  echo "INFO: Creating index $index_name on $namespace.$set($bin)"
  echo "enable; manage sindex create $index_type $index_name ns $namespace set $set bin $bin" | asadm > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo "ERROR: Could not create index $index_name on $namespace.$set($bin), exiting..."
  fi
}

# Check if asadm is installed
if ! command -v asadm &> /dev/null; then
  echo "ERROR: asadm could not be found, please install Aerospike tools, exiting..."
  exit 1
fi

# Create indexes if not exists
create_index "malware" "urlScores" "list_type" "index_url_list" "string"
create_index "malware" "urlScores" "score" "index_url_score" "numeric"
create_index "malware" "hashScores" "list_type" "idx_events_src_ip" "string"
create_index "malware" "hashScores" "score" "index_hash_score" "numeric"
create_index "malware" "ipScores" "list_type" "index_ip_list" "string"
create_index "malware" "ipScores" "score" "index_ip_score" "numeric"
create_index "malware" "controlFiles" "hash" "index_hash_controlFiles" "string"
create_index "malware" "mailQuarantine" "sensor_uuid" "index_mail_quarantine" "string"
