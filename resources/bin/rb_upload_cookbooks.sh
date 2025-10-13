#!/bin/bash

#######################################################################
# Copyright (c) 2024 ENEO Tecnologia S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

function upload_cookbook() {
  local cookbook="$1"
  
  knife cookbook upload "$cookbook" &>/dev/null
  if [[ $? -ne 0 ]]; then  
    echo "Error: Cookbook '$cookbook' could not be uploaded."
    echo "checking cookbook dependencies"

    declare -a dependencies
    if [ -d /var/chef/cookbooks/$cookbook ] && [ -f /var/chef/cookbooks/$cookbook/metadata.rb ]; then

      while IFS= read -r line; do
        if [[ $line =~ ^depends[[:space:]]+\'([a-zA-Z0-9_-]+)\'([[:space:]]|\n)* ]]; then
          dependencies+=(${BASH_REMATCH[1]})
        fi
      done < /var/chef/cookbooks/$cookbook/metadata.rb

      for dependency in ${dependencies[@]}; do
        upload_cookbook "$dependency"
        if [ $? -ne 0 ]; then
          echo "Error dependency: $dependency"
          echo "Trying to upload dependency cookbook..."
        else
          echo "dependency cookbook '$dependency' uploaded and verified successfully."
        fi
      done 
    fi
    return 1
  fi
}


listCookbooks="rb-common rb-selinux cron rb-firewall zookeeper kafka druid http2k memcached chef-server consul
               nginx geoip webui snmp rbmonitor rbscanner redis drill
               f2k logstash pmacct minio postgresql aerospike yara rbdswatcher rbevents-counter
               rsyslog freeradius rbnmsp n2klocd rbale rbcep k2http rblogstatter rb-arubacentral rbcgroup rb-exporter rb-chrony rb-clamav rb-postfix
               keepalived snort barnyard2 rbaioutliers snort3 mem2incident secor rb-druid-indexer
               rb-agents rb-reputation
               rb-proxy rb-ips rb-intrusion rb-manager" # The order matters! (please keep proxy ips and manager at the end)

max_retries=3
retry_delay=5

for n in $listCookbooks; do
  for ((retry = 1; retry <= max_retries; retry++)); do
    echo "Uploading cookbook: $n (attempt $retry/$max_retries)"
    if upload_cookbook "$n"; then
      echo "Cookbook '$n' uploaded and verified successfully."
      break
    else
      echo "Error verifying cookbook '$n'. Retrying in $retry_delay seconds..."
      sleep $retry_delay
    fi
    
    # If all retries fail, exit
    if ((retry == max_retries)); then
      echo "Error: Failed to upload and verify cookbook '$n' after $max_retries attempts."
    fi
  done
done
